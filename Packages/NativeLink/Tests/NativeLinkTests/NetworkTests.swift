import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

/// The real thing over loopback TCP: the Mac app opening a window through the control socket, a
/// device pairing with the invite's addresses, then reconnecting through `PairedHostTransport`.
@Suite struct NetworkTests {
    @Test func pairsAndReconnectsOverTCP() async throws {
        let directory = URL(filePath: "/tmp/nl-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let admitted = LinkLocked(0)
        let gateway = try LinkGateway(
            configuration: .init(
                directory: LinkGateway.Configuration.directory(inHostDirectory: directory), hostID: HostID(),
                machineName: "Loopback Mac", includesLoopback: true, preferredPort: 0, advertisesOverBonjour: false),
            keyStore: MemoryKeyStore(),
            accept: { _, _ in admitted.withLock { $0 += 1 } }
        )
        try await gateway.start()
        defer { Task { await gateway.stop() } }

        let control = LinkControlClient(hostDirectory: directory)
        await control.start()
        var status = try await waitForControl(control)
        #expect(status.listener.state == .off, "nothing listens before pairing starts")
        status = try await control.openPairingWindow()
        status = try await waitFor(control) { $0.listener.state == .listening }
        let invite = try #require(status.pairing?.invite)
        #expect(invite.addresses.contains { $0.kind == .loopback })

        let device = LinkDeviceInfo(name: "Loopback iPhone", model: "iPhone", system: "iOS 27.1")
        let decide = Task {
            _ = try await waitFor(control) { $0.pairing?.phase == .confirming }
            // People take a moment to check the numbers: longer than the connect timeout.
            try await Task.sleep(for: .seconds(5))
            try await control.decidePairing(accept: true, grants: .standard)
        }
        let (host, channel) = try await LinkPairing.pair(
            credential: .invite(invite), endpoints: LinkPairing.endpoints(for: invite, discovered: []), device: device,
            log: { _ in }, awaitingConfirmation: { _ in })
        try await decide.value
        channel.close()
        #expect(host.machineName == "Loopback Mac")
        #expect(host.addresses.contains { $0.kind == .loopback })

        let log = LinkLocked<[LinkLogEntry]>([])
        let transport = PairedHostTransport(
            host: host, device: device, log: { entry in log.withLock { $0.append(entry) } })
        let stream = try await transport.connect()
        #expect(log.withLock { $0.last?.kind } == .success)
        stream.close()
        #expect(admitted.withLock { $0 } == 2)
        await control.stop()
    }

    private func waitForControl(_ control: LinkControlClient) async throws -> LinkStatus {
        try await waitFor(control) { _ in true }
    }

    private func waitFor(_ control: LinkControlClient, _ condition: (LinkStatus) -> Bool) async throws -> LinkStatus {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let status = try? await control.refresh(), condition(status) { return status }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw MissingValue()
    }
}
