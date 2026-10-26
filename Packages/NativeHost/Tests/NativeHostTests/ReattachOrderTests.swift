import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

/// What a client passes on after re-attaching keeps its place among the host's live events, however
/// long a handler takes with it.
@Suite("Re-attach order", .timeLimit(.minutes(1)))
struct ReattachOrderTests {
    @Test("A re-attach's summary never overtakes a newer one while a handler is busy with it")
    func summaryKeepsItsPlace() async throws {
        let session = HostSessionID()
        let host = ScriptedHost(session: session)
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        let gate = HandlerGate()
        let heard = PhaseLog()
        await client.addEventHandler { event in
            guard case .sessionChanged(let summary) = event else { return }
            // The re-attach's answer: still working. The handler takes its time with it.
            if summary.phase == .prompting { await gate.pass() }
            await heard.append(summary.phase)
        }
        await client.start()
        _ = try await client.connected()
        try await client.attach(session)

        host.cut()
        try await waitUntil("the re-attach's summary reaches the handler") { await gate.isHolding }
        // Meanwhile the turn ends, and the host says so on the new connection.
        try host.publish(.idle)
        // Time for the newer summary to overtake, if anything let it.
        try await Task.sleep(for: .milliseconds(300))
        await gate.open()

        try await waitUntil("both summaries handled") { await heard.phases.count == 2 }
        #expect(await heard.phases == [.prompting, .idle])
        await client.stop()
    }

    private func waitUntil(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// A host that answers the handshake and attaches with the session working, and sends the session's
/// summaries when a test says. `cut()` drops the connection; the client comes straight back.
private final class ScriptedHost: HostTransport {
    let session: HostSessionID
    private let epoch = UUID()
    private let current = Mutex<JSONRPCPeer?>(nil)

    init(session: HostSessionID) {
        self.session = session
    }

    var displayName: String { "Scripted host" }

    func summary(_ phase: HostSessionPhase) -> HostSessionSummary {
        HostSessionSummary(
            id: session, agentID: "fake", agentName: "Fake Agent", agentSessionID: nil, cwd: "/tmp", phase: phase)
    }

    func cut() {
        current.withLock { $0 }?.close()
    }

    func publish(_ phase: HostSessionPhase) throws {
        try current.withLock { $0 }?.notify(
            HostProtocol.Method.sessionChanged, SessionChangedNotification(summary: summary(phase)))
    }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let box = ScriptedPeerBox()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "scripted-host"), label: "scripted-host") {
            [self] event in
            guard case .request(let message) = event, let id = message.id, let peer = await box.peer else { return }
            switch message.method {
            case HostProtocol.Method.initialize:
                try? peer.respond(
                    to: id,
                    with: HostInfo(
                        protocolVersion: HostProtocol.version, hostID: HostID(), machineName: "Scripted",
                        hostInfo: PeerInfo(name: "Native Host", version: "1", build: "1"), epoch: epoch,
                        processID: 1, startedAt: .now, channel: "tests"))
            case HostProtocol.Method.attach:
                try? peer.respond(to: id, with: AttachResult(summary: summary(.prompting)))
            default:
                try? peer.respond(to: id, error: .methodNotFound(message.method))
            }
        }
        await box.set(peer)
        current.withLock { $0 = peer }
        peer.start()
        return ByteChannel.socket(clientEnd, label: "client")
    }
}

private actor ScriptedPeerBox {
    var peer: JSONRPCPeer?
    func set(_ peer: JSONRPCPeer) { self.peer = peer }
}

/// Holds whoever passes until it opens.
private actor HandlerGate {
    private var held: CheckedContinuation<Void, Never>?
    private var isOpen = false

    var isHolding: Bool { held != nil }

    func pass() async {
        guard !isOpen else { return }
        await withCheckedContinuation { held = $0 }
    }

    func open() {
        isOpen = true
        held?.resume()
        held = nil
    }
}

private actor PhaseLog {
    private(set) var phases: [HostSessionPhase] = []

    func append(_ phase: HostSessionPhase) { phases.append(phase) }
}
