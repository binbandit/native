import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

/// The paired-device gateway under the host's policy (docs/enterprise/host-policy.md): a host whose
/// policy denies devices never listens or advertises, not for devices paired before and not for the
/// pair command, and revoking it closes what's open while keeping the pairings and the host's key.
@Suite struct GatewayPolicyTests {
    @Test func aDeniedHostNeverListensForDevicesPairedBefore() async throws {
        let directory = URL(filePath: "/tmp/nl-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = MemoryKeyStore()
        let before = try LinkGateway(
            configuration: .init(directory: directory, hostID: HostID(), machineName: "Test Mac", usesNetwork: false),
            keyStore: keys, accept: { _, _ in })
        let (paired, _) = try await PolicyDevice.pair(with: before)
        let hostKey = await before.status.hostKey

        // The host starts again under a policy that denies devices, with the network on this time.
        let gateway = try LinkGateway(
            configuration: .init(
                directory: directory, hostID: HostID(), machineName: "Test Mac", preferredPort: 0,
                usesNetwork: true, advertisesOverBonjour: true),
            keyStore: keys, allowedByPolicy: false, accept: { _, _ in })
        let listenerStates = LinkLocked<[LinkListenerStatus.State]>([])
        await gateway.observe { status in listenerStates.withLock { $0.append(status.listener.state) } }
        try await gateway.start()
        await gateway.openPairingWindow()
        await #expect(throws: LinkError.disabledByPolicy) {
            _ = try await PolicyDevice.connect(paired, to: gateway)
        }
        try await Task.sleep(for: .milliseconds(200))

        let status = await gateway.status
        #expect(status.isAllowedByPolicy == false)
        #expect(status.listener.state == .off)
        #expect(listenerStates.value.allSatisfy { $0 == .off }, "nothing ever tried to listen or advertise")
        #expect(status.pairing == nil)
        #expect(status.devices.map(\.device.name) == [PolicyDevice.info.name], "the pairing is kept")
        #expect(status.hostKey == hostKey, "and so is the host's key")
        await gateway.stop()
    }

    @Test func thePairCommandOnADeniedHostPrintsNoLink() async throws {
        let hostDirectory = URL(filePath: "/tmp/nl-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: hostDirectory) }
        let gateway = try LinkGateway(
            configuration: .init(
                directory: LinkGateway.Configuration.directory(inHostDirectory: hostDirectory), hostID: HostID(),
                machineName: "Test Mac", usesNetwork: false),
            keyStore: MemoryKeyStore(), allowedByPolicy: false, accept: { _, _ in })
        try await gateway.start()
        let lines = LinkLocked<[String]>([])
        let command = LinkPairCommand(
            options: LinkPairCommand.Options(grants: LinkGrants(runCommands: true), printsJSON: true),
            hostDirectory: hostDirectory, build: PeerInfo(name: "Native Host", version: "1.4.0", build: "140"),
            output: { line, _ in lines.withLock { $0.append(line) } })

        #expect(await command.run() == LinkPairCommand.ExitStatus.failed)
        let events = lines.value.compactMap(LinkPairCommandEvent.init(line:))
        #expect(events.map(\.event) == [.failed])
        #expect(events.first?.failure == .notAllowed)
        #expect(await gateway.status.pairing == nil)
        await gateway.stop()
    }

    @Test func revokingTurnsAwayAWaitingDeviceAndClosesConnectionsButKeepsPairings() async throws {
        let harness = try GatewayHarness(confirmationTimeout: .seconds(30))
        let (paired, _) = try await harness.pairDevice()
        let hostKey = await harness.gateway.status.hostKey
        #expect(await harness.gateway.status.activeDevices.first?.isConnected == true)

        // A second device proves the code and waits for someone at the host to confirm it.
        let invite = try require(await harness.gateway.openPairingWindow().pairing?.invite)
        let waiting = Task {
            try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
                device: LinkDeviceInfo(name: "Other iPad", model: "iPad", system: "iPadOS 27.1"),
                awaitingConfirmation: { _ in })
        }
        while await harness.gateway.status.pairing?.phase != .confirming {
            try await Task.sleep(for: .milliseconds(10))
        }

        await harness.gateway.setAllowedByPolicy(false)

        await #expect(throws: (any Error).self) { _ = try await waiting.value }
        try await Task.sleep(for: .milliseconds(100))
        let status = await harness.gateway.status
        #expect(status.pairing == nil)
        #expect(status.activeDevices.map(\.device.name) == ["Test iPhone"])
        #expect(status.activeDevices.first?.isConnected == false)
        #expect(status.hostKey == hostKey)
        await #expect(throws: LinkError.disabledByPolicy) { _ = try await harness.connect(paired) }

        // Allowed again, the same pairing connects as before.
        await harness.gateway.setAllowedByPolicy(true)
        _ = try await harness.connect(paired)
    }
}

/// A device pairing with and connecting to a gateway over socket pairs.
private enum PolicyDevice {
    static let info = LinkDeviceInfo(name: "Test iPhone", model: "iPhone", system: "iOS 27.1")

    static func pair(with gateway: LinkGateway) async throws -> (PairedHost, SecureChannel) {
        let invite = try require(await gateway.openPairingWindow().pairing?.invite)
        let identity = LinkIdentity()
        async let answer: Void = {
            while await gateway.status.pairing?.phase != .confirming {
                try? await Task.sleep(for: .milliseconds(10))
            }
            await gateway.decidePairing(accept: true)
        }()
        let (channel, result) = try await LinkInitiator.pair(
            over: try connection(to: gateway), identity: identity, credential: .invite(invite), device: info,
            awaitingConfirmation: { _ in })
        await answer
        await gateway.closePairingWindow()
        return (PairedHost(result: result, identity: identity), channel)
    }

    static func connect(_ host: PairedHost, to gateway: LinkGateway) async throws -> SecureChannel {
        try await LinkInitiator.connect(
            over: try connection(to: gateway), identity: try host.identity(), hostKey: host.hostKey, device: info)
    }

    private static func connection(to gateway: LinkGateway) throws -> any ByteStream {
        let (deviceEnd, hostEnd) = try UnixSocket.pair()
        gateway.serve(ByteChannel.socket(hostEnd, label: "host"))
        return ByteChannel.socket(deviceEnd, label: "device")
    }
}
