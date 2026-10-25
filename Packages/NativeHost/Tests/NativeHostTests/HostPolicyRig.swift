import ACP
import Exec
import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

// A scratch host for `HostPolicyTests`: no app, a policy the test changes, and stand-ins that count
// every side effect the policy has to stop.

/// What the host did that the policy may have to stop.
final class PolicyProbe: Sendable {
    private let counts = Mutex([String: Int]())
    func count(_ what: String) { counts.withLock { $0[what, default: 0] += 1 } }
    private func value(_ what: String) -> Int { counts.withLock { $0[what, default: 0] } }
    var shellReads: Int { value("shell") }
    var commands: Int { value("command") }
    var cancelledCommands: Int { value("cancelled") }
    var updateChecks: Int { value("update") }
}

/// Holds an operation open until the test lets it go.
final class PolicyGate: Sendable {
    private let isOpen = Mutex(false)
    func open() { isOpen.withLock { $0 = true } }
    func wait() async {
        while !isOpen.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

/// A policy the test changes, as an administrator installing or removing a profile would.
final class SwitchablePolicy: HostPolicySource {
    private let value: Mutex<HostPolicy>
    init(_ policy: HostPolicy) { value = Mutex(policy) }
    func current() -> HostPolicy { value.withLock { $0 } }
    func set(_ policy: HostPolicy) { value.withLock { $0 = policy } }
}

/// Counts commands instead of running them, and with `holds`, keeps each running until cancelled.
struct PolicyCommandRunner: CommandRunner {
    let probe: PolicyProbe
    let holds: Bool

    func run(_ command: Command) async throws -> CommandResult {
        try await run(command) { _ in }
    }

    func run(_ command: Command, onOutput: @escaping @Sendable (CommandOutput) -> Void) async throws -> CommandResult {
        probe.count("command")
        if holds {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                probe.count("cancelled")
                throw error
            }
        }
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}

/// A standalone host's updater that only counts its checks (each would reach the network).
final class PolicyUpdater: HostSelfUpdater {
    let probe: PolicyProbe
    let gate: PolicyGate?
    let activated = Mutex<[String]>([])

    init(probe: PolicyProbe, gate: PolicyGate? = nil) {
        self.probe = probe
        self.gate = gate
    }

    func checkAndStage() async throws -> HostUpdateStatus.Release? {
        probe.count("update")
        await gate?.wait()
        return HostUpdateStatus.Release(version: "2.0.0", build: "200")
    }

    func activate(build: String) throws { activated.withLock { $0.append(build) } }
    func lastRollback() -> HostUpdateStatus.Rollback? { nil }
}

/// A doctor machine that counts what it would run.
struct PolicyDoctorMachine: HostDoctorMachine {
    let probe: PolicyProbe
    var userName: String { "test" }
    var homeDirectory: String { "/tmp" }
    /// Every tool the doctor looks for is there, so its checks would run each one.
    func isExecutableFile(atPath path: String) -> Bool { true }
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) async -> HostDoctorOutput? {
        probe.count("command")
        return nil
    }
    func availableSpace(at path: String) -> Int64? { nil }
    func networkAddresses() -> [String] { [] }
    func acceptsConnections(onPort port: UInt16) async -> Bool { false }
}

/// A scratch host in this process, with no app, and the probe standing in for its side effects.
final class PolicyRig: Sendable {
    let root: URL
    let policy: SwitchablePolicy
    let probe = PolicyProbe()
    let exits = Recorded<Int32>()
    let core: HostCore
    private let ownsRoot: Bool

    @HostActor
    init(
        _ policy: HostPolicy, root: URL? = nil, updater: PolicyUpdater? = nil, holdsCommands: Bool = false,
        shell: PolicyGate? = nil, checkInterval: Duration = .milliseconds(20)
    ) throws {
        self.root =
            root
            ?? FileManager.default.temporaryDirectory.appending(
                path: "host-policy-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        ownsRoot = root == nil
        self.policy = SwitchablePolicy(policy)
        let probe = probe
        let exits = exits
        try FileManager.default.createDirectory(
            at: self.root.appending(path: "agent", directoryHint: .isDirectory), withIntermediateDirectories: true)
        core = try HostCore(
            configuration: HostCore.Configuration(
                location: HostLocation(directory: self.root.appending(path: "host", directoryHint: .isDirectory)),
                hostInfo: PeerInfo(name: "test", version: "1.0.0", build: "100"), machineName: "test", bootTime: nil,
                environment: {
                    probe.count("shell")
                    await shell?.wait()
                    return ProcessInfo.processInfo.environment
                },
                heartbeatInterval: .milliseconds(50),
                pluginsDirectory: self.root.appending(path: "plugins", directoryHint: .isDirectory),
                updates: updater.map {
                    HostUpdateEnvironment(
                        provider: .standalone,
                        current: HostUpdateStatus.Build(version: "1.0.0", build: "100", channel: "stable"),
                        selfUpdater: $0, checkInterval: checkInterval)
                },
                exit: { exits.append($0) },
                commands: PolicyCommandRunner(probe: probe, holds: holdsCommands),
                doctor: HostDoctor(machine: PolicyDoctorMachine(probe: probe), platform: nil),
                policy: self.policy, policyRefreshInterval: .milliseconds(20)))
    }

    deinit {
        if ownsRoot { try? FileManager.default.removeItem(at: root) }
    }

    var agentStore: URL { root.appending(path: "agent", directoryHint: .isDirectory) }
    private var spawnLog: URL { root.appending(path: "spawns.log") }

    /// The fake agent, behind a shell that notes every time the host spawns it.
    func agentSpec(id: String = "fake", env: [String: String] = [:]) -> AgentSpec {
        AgentSpec(
            id: id, name: id == "fake" ? "Fake Agent" : "Other Agent", command: "/bin/sh",
            args: ["-c", #"echo spawned >> "$SPAWN_LOG"; exec "$FAKE_AGENT""#],
            env: env.merging([
                "SPAWN_LOG": spawnLog.path(percentEncoded: false),
                "FAKE_AGENT": HostHarness.products.appending(path: "FakeACPAgent").path(percentEncoded: false),
                "FAKE_AGENT_STORE": agentStore.path(percentEncoded: false),
            ]) { $1 })
    }

    var spawns: Int {
        ((try? String(contentsOf: spawnLog, encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    var agentReceived: [String] {
        let log = (try? String(contentsOf: agentStore.appending(path: "received.log"), encoding: .utf8)) ?? ""
        return log.split(separator: "\n").map(String.init)
    }

    /// Native's tools for agents remember their port once they listen.
    var toolsListenerStarted: Bool {
        FileManager.default.fileExists(atPath: root.appending(path: "host/MCP").path(percentEncoded: false))
    }

    func expectNothingRan(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(spawns == 0, "an agent process", sourceLocation: sourceLocation)
        #expect(probe.shellReads == 0, "the login shell", sourceLocation: sourceLocation)
        #expect(probe.commands == 0, "a command", sourceLocation: sourceLocation)
        #expect(probe.updateChecks == 0, "an update check", sourceLocation: sourceLocation)
    }

    /// A session the agent saved, as a previous run leaves it in the store.
    @HostActor
    func seedSession() throws -> HostSessionID {
        let id = HostSessionID()
        try core.store.replaceAgents([agentSpec()])
        try core.store.insertSession(
            StoredSession(
                id: id, agentID: "fake", agentSessionID: SessionID("agent-session"), cwd: root.path(), parentID: nil,
                origin: .user))
        return id
    }

    /// A session with a turn the previous run didn't finish and a message queued behind it, as a
    /// host that crashed mid-turn leaves its store.
    @HostActor
    func seedInterruptedTurn() throws -> HostSessionID {
        let id = try seedSession()
        try core.store.beginTurn(UnfinishedTurn(sessionID: id, prompt: OutgoingPrompt(text: "work"), kind: .prompt))
        try core.store.setQueue(
            [StoredQueueItem(prompt: OutgoingPrompt(text: "then this"), isSteering: false)], for: id)
        return id
    }

    @HostActor
    func connect(_ grants: ClientGrants) async throws -> NativeHostClient {
        let core = core
        let client = NativeHostClient(
            transport: InProcessTransport { stream in await core.accept(stream, grants: grants) },
            clientInfo: PeerInfo(name: "client", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        return client
    }

    /// One raw request, as a client the host's own types don't describe would send it.
    @HostActor
    func request(_ method: String, grants: ClientGrants) async throws -> JSONValue {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        core.accept(ByteChannel.socket(hostEnd, label: "host"), grants: grants)
        let peer = JSONRPCPeer(channel: ByteChannel.socket(clientEnd, label: "client"), label: "raw") { _ in }
        peer.start()
        defer { peer.close() }
        return try await peer.request(method, EmptyMessage(), as: JSONValue.self)
    }

    func waitUntil(_ what: String, _ condition: @HostActor () throws -> Bool) async throws {
        for _ in 0..<250 {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out waiting for \(what)")
    }

    /// Ends any agent the test started.
    @HostActor
    func stop() {
        for link in core.agents.values { link.endNow() }
    }
}

extension HostCore {
    /// The catalog without a client, as a host restarted with its store has it.
    func syncAgentsForTests(_ specs: [AgentSpec]) {
        try? syncAgents(specs)
    }
}
