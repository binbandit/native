import Foundation
import NativeHostProtocol

// Each connection, from the hello to an admitted host-protocol stream, and the network listener.
extension LinkGateway {
    static let linkVersion = 1
    static let handshakeTimeout: Duration = .seconds(10)

    /// Serves one incoming connection: TCP from the listener, or a socket pair in tests.
    public nonisolated func serve(_ raw: any ByteStream) {
        Task { await handle(raw) }
    }

    private func handle(_ raw: any ByteStream) async {
        // A device that goes quiet mid-handshake doesn't keep its connection.
        let watchdog = Task {
            try await Task.sleep(for: Self.handshakeTimeout)
            raw.close()
        }
        defer { watchdog.cancel() }
        let reader = LinkFrameReader(raw.incoming())
        do {
            let hello: LinkHello
            do {
                hello = try LinkHello(bytes: try await reader.next().body)
            } catch LinkError.refused(let refusal) {
                return refuse(raw, refusal)
            }

            var preSharedKey: Data?
            var windowID: UUID?
            if hello.mode != .connect {
                guard let window else { return refuse(raw, .noPairingWindow) }
                do {
                    preSharedKey = try window.preSharedKey(for: hello.mode, now: configuration.now())
                } catch {
                    return refuse(raw, error)
                }
                windowID = window.id
            }

            var noise = try NoiseHandshake(
                pattern: hello.pattern, isInitiator: false, prologue: hello.bytes, localStatic: identity.privateKey,
                preSharedKey: preSharedKey)
            _ = try noise.readMessage(try await reader.next().body)
            let hostHello = LinkHostHello(
                hostID: configuration.hostID, name: configuration.machineName, linkVersion: Self.linkVersion)
            guard raw.write(LinkFrame(kind: .noise, body: try noise.writeMessage(payload: JSONEncoder().encode(hostHello))).encoded)
            else { return raw.close() }

            let final = try await reader.next()
            let deviceInfo: LinkDeviceInfo
            do {
                deviceInfo = try JSONDecoder().decode(LinkDeviceInfo.self, from: try noise.readMessage(final.body))
            } catch NoiseError.decryptFailed where windowID != nil {
                // In a pairing handshake only the pre-shared key can make the last message fail.
                return refuse(raw, recordWrongCode(windowID: windowID))
            }
            guard let remoteStatic = noise.remoteStatic else { return raw.close() }
            let channel = SecureChannel(
                raw: raw, reader: reader, ciphers: try noise.split(), remoteKey: LinkPublicKey(remoteStatic),
                handshakeHash: noise.handshakeHash)
            watchdog.cancel()
            if let windowID {
                await pair(channel, deviceInfo: deviceInfo, usedCode: hello.mode == .pairWithCode, windowID: windowID)
            } else {
                admit(channel, welcome: .ok)
            }
        } catch {
            raw.close()
        }
    }

    private func refuse(_ raw: any ByteStream, _ refusal: LinkRefusal) {
        raw.write(LinkFrame(kind: .refusal, body: Data([refusal.rawValue])).encoded)
        raw.close()
    }

    private func recordWrongCode(windowID: UUID?) -> LinkRefusal {
        guard var current = window, current.id == windowID else { return .noPairingWindow }
        let refusal = current.recordFailure()
        window = current
        publish()
        return refusal
    }

    /// The device proved the window's secret. The window is spent from here on: whatever the Mac's
    /// user decides, the same code never pairs anyone else.
    private func pair(_ channel: SecureChannel, deviceInfo: LinkDeviceInfo, usedCode: Bool, windowID: UUID) async {
        guard var current = window, current.id == windowID, current.phase == .open else {
            try? channel.send(LinkWelcome(status: .expired))
            return channel.close()
        }
        let verification = VerificationCode(handshakeHash: channel.handshakeHash)
        current.phase = .confirming
        current.request = LinkPairingRequest(device: deviceInfo, verification: verification, usedCode: usedCode)
        window = current
        publish()
        try? channel.send(LinkWelcome(status: .awaitingConfirmation, verification: verification))

        let outcome = await awaitDecision()
        guard var current = window, current.id == windowID else {
            // The sheet closed or a new code was made while waiting.
            try? channel.send(LinkWelcome(status: .rejected))
            return channel.close()
        }
        switch outcome {
        case .accepted(let grants):
            let device = LinkDevice(
                info: deviceInfo, publicKey: channel.remoteKey, pairedAt: configuration.now(), grants: grants)
            registry.add(device)
            registry.isEnabled = true
            save()
            current.phase = .paired
            current.pairedDeviceID = device.id
            window = current
            admit(channel, welcome: .paired)
        case .rejected:
            current.phase = .rejected
            window = current
            try? channel.send(LinkWelcome(status: .rejected))
            channel.close()
        case .expired:
            current.phase = .expired
            window = current
            try? channel.send(LinkWelcome(status: .expired))
            channel.close()
        }
        publish()
    }

    private func awaitDecision() async -> PairingDecision {
        resolveDecision(.rejected)
        let timeout = configuration.confirmationTimeout
        let timer = Task {
            try await Task.sleep(for: timeout)
            self.resolveDecision(.expired)
        }
        defer { timer.cancel() }
        return await withCheckedContinuation { continuation in
            decision = continuation
        }
    }

    /// Lets a paired device in, or tells it why not.
    private func admit(_ channel: SecureChannel, welcome: LinkWelcome.Status) {
        guard let device = registry.device(withKey: channel.remoteKey) else {
            try? channel.send(LinkWelcome(status: .unknownDevice))
            return channel.close()
        }
        guard !device.isRevoked, registry.isEnabled else {
            try? channel.send(LinkWelcome(status: device.isRevoked ? .revoked : .unknownDevice))
            return channel.close()
        }
        registry.update(device.id) { $0.lastSeen = configuration.now() }
        save()
        do {
            try channel.send(LinkWelcome(status: welcome, deviceID: device.id, grants: device.grants))
        } catch {
            return channel.close()
        }
        connections[device.id, default: [:]][ObjectIdentifier(channel)] = channel
        channel.onClose { [weak self] in
            Task { await self?.closed(channel, deviceID: device.id) }
        }
        accept(LinkPolicyStream(channel: channel, grants: device.grants, deviceName: device.name), device.grants)
        publish()
    }

    private func closed(_ channel: SecureChannel, deviceID: UUID) {
        guard connections[deviceID]?.removeValue(forKey: ObjectIdentifier(channel)) != nil else { return }
        if connections[deviceID]?.isEmpty == true { connections[deviceID] = nil }
        registry.update(deviceID) { $0.lastSeen = configuration.now() }
        save()
        publish()
    }

    // MARK: - Listener

    /// Listens while the gateway is on and there's someone to serve: a paired device or an open window.
    func updateListener() {
        let shouldListen =
            configuration.usesNetwork && registry.isEnabled && (!registry.activeDevices.isEmpty || window != nil)
        if shouldListen, listener == nil {
            startListener(port: registry.port ?? configuration.preferredPort)
        } else if !shouldListen, let listener {
            listener.cancel()
            self.listener = nil
            listenerStatus = LinkListenerStatus(state: .off)
        }
    }

    private func startListener(port: UInt16?) {
        listenerStatus = LinkListenerStatus(state: .starting, port: port)
        do {
            listener = try LinkListener(
                port: port, serviceName: configuration.machineName,
                txtRecord: ["v": "\(Self.linkVersion)", "k": identity.publicKey.fingerprint, "i": configuration.hostID.description],
                events: { [weak self] event in Task { await self?.listenerEvent(event, requestedPort: port) } },
                connections: { [weak self] stream in self?.serve(stream) }
            )
        } catch {
            listenerStatus = LinkListenerStatus(state: .failed, problem: error.localizedDescription)
        }
    }

    private func listenerEvent(_ event: LinkListener.Event, requestedPort: UInt16?) {
        switch event {
        case .ready(let port):
            listenerStatus = LinkListenerStatus(state: .listening, port: port)
            if registry.port != port {
                registry.port = port
                save()
            }
            logger.info("Listening for paired devices on port \(port)")
        case .failed(let problem, let addressInUse):
            listener = nil
            if addressInUse, requestedPort != nil {
                // Another Native on this Mac has the port: take any free one and remember it.
                startListener(port: nil)
                return
            }
            listenerStatus = LinkListenerStatus(state: .failed, problem: problem)
            logger.error("Listener failed: \(problem)")
        }
        publish()
    }
}
