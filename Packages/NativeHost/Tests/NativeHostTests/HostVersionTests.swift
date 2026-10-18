import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@Suite("Host versions")
struct HostVersionTests {
    @Test("Builds compare as numbers; a newer host means the app is outdated")
    func comparison() {
        #expect(
            HostVersionStatus.compare(appBuild: "42", hostBuild: "42", hostVersion: "1.2", workingTasks: 3) == .matched)
        #expect(
            HostVersionStatus.compare(appBuild: "42", hostBuild: "41", hostVersion: "1.1", workingTasks: 2)
                == .hostRestartPending(hostVersion: "1.1", workingTasks: 2))
        #expect(
            HostVersionStatus.compare(appBuild: "9", hostBuild: "10", hostVersion: "1.3", workingTasks: 0)
                == .appOutdated(hostVersion: "1.3"))
        // Not numbers: the app's own host wins.
        #expect(
            HostVersionStatus.compare(appBuild: "dev", hostBuild: "1", hostVersion: "1.0", workingTasks: 0)
                == .hostRestartPending(hostVersion: "1.0", workingTasks: 0))
    }

    @Test("Shutdown requests from older apps decode without `immediately`")
    func shutdownDefault() throws {
        let old = try JSONDecoder().decode(ShutdownParams.self, from: Data(#"{"stopAgents":false}"#.utf8))
        #expect(!old.stopAgents && !old.immediately)
        let now = try JSONDecoder().decode(
            ShutdownParams.self, from: Data(#"{"stopAgents":false,"immediately":true}"#.utf8))
        #expect(now.immediately)
    }

    @Test("An older host is asked to restart once idle; a newer one is left alone", arguments: [0, 99])
    func olderHostAskedToStop(hostProtocol: Int) async throws {
        let host = FakeHost(protocolVersion: hostProtocol)
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "2.0", build: "2"))
        await client.start()
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, await !Self.isIncompatible(client.state) {
            try await Task.sleep(for: .milliseconds(20))
        }
        await client.stop()
        #expect(await client.state == .incompatible(protocolVersion: hostProtocol, host: FakeHost.info))
        // Only an older host is asked, and only to restart: never to stop its agents.
        #expect(
            host.shutdowns
                == (hostProtocol < HostProtocol.version ? [#"{"immediately":false,"stopAgents":false}"#] : []))
    }

    private static func isIncompatible(_ state: NativeHostClient.ConnectionState) -> Bool {
        if case .incompatible = state { true } else { false }
    }
}

/// A host of another protocol version: it answers only the frozen handshake, with a result shaped
/// unlike today's `HostInfo`, and records shutdown requests.
private final class FakeHost: HostTransport {
    static let info = PeerInfo(name: "Native Host", version: "0.9", build: "1")
    let protocolVersion: Int
    private let recorded = Mutex<[String]>([])

    init(protocolVersion: Int) {
        self.protocolVersion = protocolVersion
    }

    var shutdowns: [String] {
        recorded.withLock { $0 }
    }

    var displayName: String { "Fake host" }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let box = PeerBox()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "fake-host"), label: "fake-host") {
            [self] event in
            guard case .request(let message) = event, let id = message.id, let peer = await box.peer else { return }
            switch message.method {
            case HostProtocol.Method.initialize:
                try? peer.respond(
                    to: id,
                    with: JSONValue.object([
                        "protocolVersion": .number(Double(protocolVersion)),
                        "hostInfo": .object([
                            "name": .string("Native Host"), "version": .string("0.9"), "build": .string("1"),
                        ]),
                        "somethingElse": .bool(true),
                    ]))
            case HostProtocol.Method.shutdown:
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let params = try? message.params(as: ShutdownParams.self)
                let text = params.flatMap { try? encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? "?"
                recorded.withLock { $0.append(text) }
                try? peer.respond(to: id, with: EmptyMessage())
            default:
                try? peer.respond(to: id, error: .methodNotFound(message.method))
            }
        }
        await box.set(peer)
        peer.start()
        return ByteChannel.socket(clientEnd, label: "client")
    }
}

private actor PeerBox {
    var peer: JSONRPCPeer?
    func set(_ peer: JSONRPCPeer) { self.peer = peer }
}
