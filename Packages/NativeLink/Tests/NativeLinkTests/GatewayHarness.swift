import Foundation
import NativeHostProtocol

@testable import NativeLink

/// A gateway with no network: connections are socket pairs, the clock is the test's, and admitted
/// streams land in `admitted` the way they'd reach the host.
final class GatewayHarness: Sendable {
    let gateway: LinkGateway
    let directory: URL
    let clock: LinkLocked<Date>
    let admitted = LinkLocked<[(any ByteStream, LinkGrants)]>([])
    let device = LinkDeviceInfo(name: "Test iPhone", model: "iPhone", system: "iOS 27.1")

    init(confirmationTimeout: Duration = .seconds(5)) throws {
        // Short: the control socket's path has to fit in sockaddr_un.
        directory = URL(filePath: "/tmp/nl-\(UUID().uuidString.prefix(8))")
        let clock = LinkLocked(Date(timeIntervalSince1970: 1_800_000_000))
        self.clock = clock
        let admitted = admitted
        gateway = try LinkGateway(
            configuration: .init(
                directory: directory, hostID: HostID(), machineName: "Test Mac", confirmationTimeout: confirmationTimeout,
                usesNetwork: false, now: { clock.value }),
            keyStore: MemoryKeyStore(),
            accept: { stream, grants in admitted.withLock { $0.append((stream, grants)) } }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func advance(by seconds: TimeInterval) {
        clock.withLock { $0 += seconds }
    }

    /// A fresh connection to the gateway: the device's end.
    func connection() throws -> any ByteStream {
        let (deviceEnd, hostEnd) = try UnixSocket.pair()
        gateway.serve(ByteChannel.socket(hostEnd, label: "host"))
        return ByteChannel.socket(deviceEnd, label: "device")
    }

    /// Answers the next pairing request on the gateway the way the Mac's user would.
    func answerNextRequest(accept: Bool, grants: LinkGrants = .standard) async {
        while await gateway.status.pairing?.phase != .confirming {
            try? await Task.sleep(for: .milliseconds(10))
        }
        await gateway.decidePairing(accept: accept, grants: grants)
    }

    /// Opens a window, pairs a new device with its invite, and returns what the device keeps.
    func pairDevice(grants: LinkGrants = .standard) async throws -> (PairedHost, SecureChannel) {
        let invite = try require(await gateway.openPairingWindow().pairing?.invite)
        let identity = LinkIdentity()
        async let answer: Void = answerNextRequest(accept: true, grants: grants)
        let (channel, result) = try await LinkInitiator.pair(
            over: try connection(), identity: identity, credential: .invite(invite), device: device,
            awaitingConfirmation: { _ in })
        await answer
        return (PairedHost(result: result, identity: identity), channel)
    }

    func connect(_ host: PairedHost) async throws -> SecureChannel {
        try await LinkInitiator.connect(over: try connection(), identity: try host.identity(), hostKey: host.hostKey, device: device)
    }
}

struct MissingValue: Error {}

func require<Value>(_ value: Value?) throws -> Value {
    guard let value else { throw MissingValue() }
    return value
}
