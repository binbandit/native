import Foundation
import NativeHostProtocol

/// What pairing established, for the device to keep.
public struct LinkPairingResult: Sendable {
    public let hostID: HostID
    public let hostKey: LinkPublicKey
    public let hostName: String
    public let deviceID: UUID
    public let grants: LinkGrants
    public let addresses: [LinkAddress]
}

/// The device's side of a link connection, over any byte stream (TCP, or a socket pair in tests).
public enum LinkInitiator {
    public enum Credential: Sendable {
        /// Scanned or pasted: carries the host's key, so the host is pinned before anything is sent.
        case invite(PairingInvite)
        /// Typed: the host's key is learned in the handshake and confirmed by the verification code.
        case code(PairingCode)
    }

    static let handshakeTimeout: Duration = .seconds(10)

    /// Connects as a paired device. Returns once the host has accepted it; the host protocol follows.
    public static func connect(
        over raw: any ByteStream, identity: LinkIdentity, hostKey: LinkPublicKey, device: LinkDeviceInfo
    ) async throws -> SecureChannel {
        let (channel, _) = try await withTimeout(handshakeTimeout, closing: raw) {
            let (channel, hello) = try await handshake(
                over: raw, mode: .connect, identity: identity, preSharedKey: nil, expectedHostKey: hostKey,
                device: device)
            let welcome = try await channel.receive(LinkWelcome.self)
            switch welcome.status {
            case .ok: return (channel, hello)
            case .revoked: throw LinkError.revoked
            case .unknownDevice: throw LinkError.unknownDevice
            default: throw LinkError.malformed("welcome \(welcome.status.rawValue)")
            }
        }
        return channel
    }

    /// Pairs: proves the code, waits while the Mac's user confirms (`awaitingConfirmation` gets the
    /// verification code both screens show), and returns the channel, already serving the host
    /// protocol, with what to remember.
    public static func pair(
        over raw: any ByteStream, identity: LinkIdentity, credential: Credential, device: LinkDeviceInfo,
        awaitingConfirmation: @escaping @Sendable (VerificationCode) -> Void
    ) async throws -> (SecureChannel, LinkPairingResult) {
        let mode: LinkHello.Mode
        let preSharedKey: Data
        let expectedHostKey: LinkPublicKey?
        switch credential {
        case .invite(let invite):
            (mode, preSharedKey, expectedHostKey) = (.pairWithInvite, invite.preSharedKey, invite.hostKey)
        case .code(let code):
            (mode, preSharedKey, expectedHostKey) = (.pairWithCode, code.preSharedKey, nil)
        }
        let (channel, hello) = try await withTimeout(handshakeTimeout, closing: raw) {
            try await handshake(
                over: raw, mode: mode, identity: identity, preSharedKey: preSharedKey, expectedHostKey: expectedHostKey,
                device: device)
        }
        // The Mac's user may take a while; the host's own timeout ends the wait.
        while true {
            let welcome = try await channel.receive(LinkWelcome.self)
            switch welcome.status {
            case .awaitingConfirmation:
                if let verification = welcome.verification { awaitingConfirmation(verification) }
            case .paired:
                guard let deviceID = welcome.deviceID else { throw LinkError.malformed("paired without a device id") }
                let result = LinkPairingResult(
                    hostID: hello.hostID, hostKey: channel.remoteKey, hostName: hello.name, deviceID: deviceID,
                    grants: welcome.grants ?? .standard, addresses: welcome.addresses ?? [])
                return (channel, result)
            case .rejected: throw LinkError.rejected
            case .expired: throw LinkError.confirmationExpired
            default: throw LinkError.malformed("welcome \(welcome.status.rawValue)")
            }
        }
    }

    /// Hello, then `XX` or `XXpsk3`. The host's key is checked before the device reveals its own.
    private static func handshake(
        over raw: any ByteStream, mode: LinkHello.Mode, identity: LinkIdentity, preSharedKey: Data?,
        expectedHostKey: LinkPublicKey?, device: LinkDeviceInfo
    ) async throws -> (SecureChannel, LinkHostHello) {
        let hello = LinkHello(mode: mode)
        var noise = try NoiseHandshake(
            pattern: hello.pattern, isInitiator: true, prologue: hello.bytes, localStatic: identity.privateKey,
            preSharedKey: preSharedKey)
        let reader = LinkFrameReader(raw.incoming())
        guard raw.write(LinkFrame(kind: .noise, body: hello.bytes).encoded),
            raw.write(LinkFrame(kind: .noise, body: try noise.writeMessage()).encoded)
        else { throw LinkError.closed }

        let reply = try await reader.next()
        if reply.kind == .refusal { throw LinkError.refused(LinkRefusal(byte: reply.body.first)) }
        let hostHello: LinkHostHello
        do {
            hostHello = try JSONDecoder().decode(LinkHostHello.self, from: try noise.readMessage(reply.body))
        } catch is NoiseError {
            throw LinkError.handshakeFailed
        } catch {
            throw LinkError.malformed("host hello")
        }
        guard let remote = noise.remoteStatic else { throw LinkError.handshakeFailed }
        let hostKey = LinkPublicKey(remote)
        if let expectedHostKey, hostKey != expectedHostKey {
            raw.close()
            throw LinkError.hostKeyMismatch
        }
        let final = try noise.writeMessage(payload: try JSONEncoder().encode(device))
        guard raw.write(LinkFrame(kind: .noise, body: final).encoded) else { throw LinkError.closed }
        let channel = SecureChannel(
            raw: raw, reader: reader, ciphers: try noise.split(), remoteKey: hostKey, handshakeHash: noise.handshakeHash)
        return (channel, hostHello)
    }
}

/// Runs `work`, closing `stream` and throwing `LinkError.timedOut` if it takes longer than `limit`.
func withTimeout<Value: Sendable>(
    _ limit: Duration, closing stream: any ByteStream, _ work: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value?.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: limit)
            return nil
        }
        defer { group.cancelAll() }
        guard let first = try await group.next(), let value = first else {
            stream.close()
            throw LinkError.timedOut
        }
        return value
    }
}
