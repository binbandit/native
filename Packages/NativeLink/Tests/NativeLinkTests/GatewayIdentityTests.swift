import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

@Suite struct GatewayIdentityTests {
    @Test func identityIsTheHandshakeKeyRegardlessOfReportedName() async throws {
        let directory = URL(filePath: "/tmp/nl-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let admitted = LinkLocked<[(any ByteStream, LinkGrants, HostClientIdentity)]>([])
        let gateway = try LinkGateway(
            configuration: .init(directory: directory, hostID: HostID(), machineName: "Fixture", usesNetwork: false),
            keyStore: MemoryKeyStore(),
            accept: { stream, grants, identity in admitted.withLock { $0.append((stream, grants, identity)) } })
        let key = LinkIdentity()
        let grants = LinkGrants(managePlugins: false, manageHost: false, runCommands: false)
        let invite = try require(await gateway.openPairingWindow().pairing?.invite)
        async let answer: Void = {
            while await gateway.status.pairing?.phase != .confirming {
                try await Task.sleep(for: .milliseconds(10))
            }
            await gateway.decidePairing(accept: true, grants: grants)
        }()
        let (channel, paired) = try await LinkInitiator.pair(
            over: connection(gateway), identity: key, credential: .invite(invite),
            device: LinkDeviceInfo(name: "CLAIMED_ADMIN_CANARY", model: "Fixture", system: "Fixture"),
            awaitingConfirmation: { _ in })
        try await answer
        #expect(admitted.value.first?.2 == .pairedDevice(publicKey: key.publicKey.rawRepresentation))
        #expect(admitted.value.first?.1 == grants)
        channel.close()
        let reconnected = try await LinkInitiator.connect(
            over: connection(gateway), identity: key, hostKey: paired.hostKey,
            device: LinkDeviceInfo(name: "Different claimed user", model: "Fixture", system: "Fixture"))
        #expect(admitted.value.last?.2 == .pairedDevice(publicKey: key.publicKey.rawRepresentation))
        #expect(admitted.value.last?.1 == grants)
        await #expect(throws: (any Error).self) {
            _ = try await LinkInitiator.connect(
                over: connection(gateway), identity: LinkIdentity(), hostKey: paired.hostKey,
                device: LinkDeviceInfo(name: "CLAIMED_ADMIN_CANARY", model: "Fixture", system: "Fixture"))
        }
        #expect(admitted.value.count == 2)
        reconnected.close()
        await gateway.stop()
    }

    private func connection(_ gateway: LinkGateway) throws -> any ByteStream {
        let (device, host) = try UnixSocket.pair()
        gateway.serve(ByteChannel.socket(host, label: "host"))
        return ByteChannel.socket(device, label: "device")
    }
}
