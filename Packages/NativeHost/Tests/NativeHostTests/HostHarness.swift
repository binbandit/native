import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// A real `native-host` process in a scratch folder, driving the fake agent, plus a client that
/// records everything it hears. Tests kill and restart the host the way a crash would.
final class HostHarness: @unchecked Sendable {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "native-host-e2e-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    var home: URL { root.appending(path: "host", directoryHint: .isDirectory) }
    var agentStore: URL { root.appending(path: "agent", directoryHint: .isDirectory) }
    var plugins: URL { root.appending(path: "plugins", directoryHint: .isDirectory) }
    /// Where the fake agent writes the pid of the process it starts in a group of its own.
    var grandchildFile: URL { root.appending(path: "grandchild.pid") }
    /// Extra environment for the fake agent (`FAKE_AGENT_NO_STEERING`, `FAKE_AGENT_GRANDCHILD`).
    var agentEnvironment: [String: String] = [:]
    private var process: Process?

    static let products = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: ".build/debug", directoryHint: .isDirectory)

    var agentSpec: AgentSpec {
        AgentSpec(
            id: "fake", name: "Fake Agent",
            command: Self.products.appending(path: "FakeACPAgent").path(percentEncoded: false),
            env: agentEnvironment.merging(["FAKE_AGENT_STORE": agentStore.path(percentEncoded: false)]) { $1 })
    }

    /// The pid the fake agent's own child was given, once it started one.
    var grandchild: pid_t? {
        (try? String(contentsOf: grandchildFile, encoding: .utf8)).flatMap { pid_t($0) }
    }

    var location: HostLocation {
        HostLocation(directory: home)
    }

    init() throws {
        try FileManager.default.createDirectory(at: agentStore, withIntermediateDirectories: true)
    }

    deinit {
        kill()
        // Killing the host leaves what agents started in groups of their own (the case the host
        // handles when it stops agents itself); tests mustn't leave those behind.
        if let grandchild {
            Darwin.kill(grandchild, SIGKILL)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func start() throws {
        let process = Process()
        process.executableURL = Self.products.appending(path: "native-host")
        process.arguments = [
            "serve", "--home", home.path(percentEncoded: false), "--plugins", plugins.path(percentEncoded: false),
            "--inherit-environment",
        ]
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
    }

    /// SIGKILL, as a crash or `kill -9` would: no chance to clean up.
    func kill() {
        guard let process, process.isRunning else { return }
        Darwin.kill(process.processIdentifier, SIGKILL)
        // Polled: `waitUntilExit` waits on the run loop for a wakeup that sometimes never came while
        // other harnesses stopped their hosts at once (`swift test --parallel`), hanging the run.
        while process.isRunning { usleep(10_000) }
        self.process = nil
    }

    /// Waits (up to `timeout`) for the host to exit on its own and returns its exit status.
    func waitForExit(timeout: Duration = .seconds(20)) async throws -> Int32? {
        guard let process else { return nil }
        let deadline = ContinuousClock.now + timeout
        while process.isRunning, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !process.isRunning else { return nil }
        self.process = nil
        return process.terminationStatus
    }

    var hostProcessID: Int32? {
        process?.processIdentifier
    }

    /// What the fake agent received, in order: "prompt\t<text>" and "steer\t<text>" lines.
    var received: [String] {
        let text = (try? String(contentsOf: agentStore.appending(path: "received.log"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    func connect(transport: (any HostTransport)? = nil) async throws -> Recorder {
        let client = NativeHostClient(
            transport: transport ?? LocalSocketTransport(location: location),
            clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        let recorder = Recorder(client: client)
        await recorder.listen()
        await client.start()
        _ = try await recorder.wait("connect", timeout: .seconds(10)) { _ in await client.hostInfo != nil }
        try await client.syncAgents([agentSpec])
        return recorder
    }
}

/// Collects a client's events and folds each session's into a mirror.
actor Recorder {
    let client: NativeHostClient
    private(set) var mirrors: [HostSessionID: SessionMirror] = [:]
    private(set) var events: [HostSessionID: [HostEvent]] = [:]
    private(set) var summaries: [HostSessionID: HostSessionSummary] = [:]
    private(set) var agents: [String: HostAgent] = [:]
    private(set) var closed: Set<HostSessionID> = []
    private(set) var activity: [ActivityEntry] = []
    private(set) var lastPlugins: [HostPlugin]?
    init(client: NativeHostClient) {
        self.client = client
    }

    /// Records through an ordered handler, so when a request returns, everything the host sent
    /// before its answer is recorded.
    func listen() async {
        await client.addEventHandler { [weak self] event in
            await self?.record(event)
        }
    }

    private func record(_ event: NativeHostClient.Event) {
        switch event {
        case .sessionEvent(let session, let step):
            mirrors[session, default: SessionMirror()].apply(step)
            events[session, default: []].append(step.event)
        case .sessionChanged(let summary):
            summaries[summary.id] = summary
        case .sessionClosed(let session):
            closed.insert(session)
        case .agentChanged(let agent):
            agents[agent.id] = agent
        case .activity(let entry):
            activity.append(entry)
        case .pluginsChanged(let plugins):
            lastPlugins = plugins
        default:
            break
        }
    }

    func notices(_ session: HostSessionID) -> [String] {
        mirror(session).state.items.compactMap { item in
            if case .notice(let notice) = item { notice.text } else { nil }
        }
    }

    func failures(_ session: HostSessionID) -> [String] {
        payloads(session).compactMap { if case .turnFailed(let message, _) = $0 { message } else { nil } }
    }

    func mirror(_ session: HostSessionID) -> SessionMirror {
        mirrors[session] ?? SessionMirror()
    }

    func payloads(_ session: HostSessionID) -> [HostEvent.Payload] {
        events[session, default: []].map(\.payload)
    }

    func agentText(_ session: HostSessionID) -> String {
        mirror(session).state.items.compactMap { item in
            if case .message(let message) = item, message.role == .agent { message.text } else { nil }
        }.joined(separator: "\n")
    }

    func recoveries(_ session: HostSessionID) -> [RecoveryNote] {
        payloads(session).compactMap { if case .recovered(let note) = $0 { note } else { nil } }
    }

    func turnsEnded(_ session: HostSessionID) -> [String] {
        payloads(session).compactMap { if case .turnEnded(let reason) = $0 { reason } else { nil } }
    }

    /// Polls until `condition` holds, failing the test after `timeout`.
    @discardableResult
    func wait(
        _ what: String, timeout: Duration = .seconds(20), until condition: @Sendable (Recorder) async -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition(self) { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for \(what)")
        return false
    }

    func stop() async {
        await client.stop()
    }
}

/// The local socket, with a way to drop the connection as a flaky network would, without the host
/// noticing anything but a client going away.
final class CuttableTransport: HostTransport, @unchecked Sendable {
    private let base: LocalSocketTransport
    private let lock = NSLock()
    private var current: (any ByteStream)?

    init(location: HostLocation) {
        base = LocalSocketTransport(location: location)
    }

    var displayName: String { "Cuttable" }

    func connect() async throws -> any ByteStream {
        let stream = try await base.connect()
        lock.withLock { current = stream }
        return stream
    }

    func cut() {
        lock.withLock { current }?.close()
    }
}

/// Connects a client straight to an in-process host, as a paired transport would after its handshake.
struct InProcessTransport: HostTransport {
    let accept: @Sendable (any ByteStream) async -> Void

    var displayName: String { "In process" }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        await accept(ByteChannel.socket(hostEnd, label: "host"))
        return ByteChannel.socket(clientEnd, label: "client")
    }
}
