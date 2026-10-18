import ACP
import Foundation
import Observation

/// One agent's process and connection, and how starting it went. Each agent runs on its own, so
/// one failing leaves the others alone. Agents start when something needs them (`AppModel`
/// decides when) and can be parked again, so an unused one holds no process.
@Observable
final class AgentRuntime {
    typealias Status = AgentRuntimeStatus

    let agent: AgentDefinition
    private(set) var status = Status.idle
    /// The environment plugins' launch policy added when the agent last started, to tell when a
    /// changed policy needs a restart.
    var launchPolicyEnvironment: [String: String] = [:]
    /// What the agent says about itself, such as its version.
    private(set) var info: Implementation?
    private(set) var capabilities: AgentCapabilities?
    /// Ways the agent offers to sign in, for when it turns requests away with `auth_required`.
    private(set) var authMethods: [AuthMethod] = []
    /// The agent turned a request away until the user signs in.
    private(set) var needsSignIn = false
    private(set) var isSigningIn = false

    private var process: AgentProcess?
    /// The launch in flight, so callers that ask for the agent while it starts all wait for it.
    @ObservationIgnored private var launching: Task<Void, Never>?
    /// Bumped whenever the process is replaced, so events from an old one are dropped.
    private var generation = 0

    init(agent: AgentDefinition) {
        self.agent = agent
    }

    /// The connection, while the agent can take requests.
    var connection: ACPConnection? {
        status == .ready ? process?.connection : nil
    }

    var isReady: Bool {
        status == .ready
    }

    /// Whether sessions can start on the agent: it's running, on its way, or idle and starts when
    /// asked. `AppModel.ensureRunning` waits for it either way.
    var isAvailable: Bool {
        switch status {
        case .idle, .starting, .ready: true
        case .notInstalled, .failed: false
        }
    }

    /// The agent's launched process (env, which execs the agent), for resource reporting; nil while
    /// it isn't running.
    var processIdentifier: Int32? {
        process?.processIdentifier
    }

    /// Launches the agent and initializes the connection. Its events, including `.disconnected`
    /// when it exits, go to `onEvent`. While a launch is in flight, this waits for it instead.
    func start(environment: [String: String], onEvent: @escaping @MainActor (AgentEvent) -> Void) async {
        if let launching {
            return await launching.value
        }
        guard process == nil else { return }
        // Set before the launch task runs, so callers can tell a launch is under way.
        status = .starting
        let launch = Task { await self.launch(environment: environment, onEvent: onEvent) }
        launching = launch
        await launch.value
        launching = nil
    }

    /// Waits for a launch under way, if there is one.
    func finishStarting() async {
        await launching?.value
    }

    private func launch(environment: [String: String], onEvent: @escaping @MainActor (AgentEvent) -> Void) async {
        generation += 1
        let generation = generation
        needsSignIn = false
        let command = agent.command(environment: environment)
        guard Self.isInstalled(command) else {
            status = .notInstalled(command: command.executable)
            return
        }
        do {
            let process = try AgentProcess(command) { [weak self] event in
                await self?.receive(event, generation: generation, onEvent: onEvent)
            }
            self.process = process
            await process.start()
            let response = try await process.connection.send(InitializeRequest(clientInfo: Self.clientInfo))
            guard generation == self.generation else { return }
            guard response.protocolVersion == ACP.protocolVersion else {
                throw RPCError(code: 0, message: "\(agent.displayName) speaks ACP version \(response.protocolVersion); Native supports version \(ACP.protocolVersion).")
            }
            info = response.agentInfo
            capabilities = response.agentCapabilities
            authMethods = response.authMethods
            status = .ready
        } catch {
            guard generation == self.generation else { return }
            fail(error.localizedDescription)
        }
    }

    /// Ends the process. Nothing it sends from here on is delivered.
    func stop() {
        generation += 1
        process?.terminate()
        process = nil
    }

    /// Ends a running agent's process to give its memory back, leaving it to start again when
    /// something needs it. Its sessions go with the process; the caller drops their models.
    func park() {
        guard status == .ready else { return }
        stop()
        status = .idle
        needsSignIn = false
    }

    /// Signs in with one of `authMethods`. The agent may open a browser and wait for the user.
    func signIn(with method: AuthMethod) async throws {
        guard let connection else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        _ = try await connection.send(AuthenticateRequest(methodId: method.id))
        needsSignIn = false
    }

    /// Records whether `error` is the agent asking the user to sign in.
    @discardableResult
    func noteSignInRequired(by error: any Error) -> Bool {
        guard (error as? RPCError)?.isAuthRequired == true else { return false }
        needsSignIn = true
        return true
    }

    private func receive(_ event: AgentEvent, generation: Int, onEvent: @MainActor (AgentEvent) -> Void) {
        // Ignore stragglers from a process we've already replaced.
        guard generation == self.generation else { return }
        if case .disconnected = event {
            fail("\(agent.displayName) exited.")
        }
        onEvent(event)
    }

    private func fail(_ message: String) {
        // A dying agent reports twice (EOF, then the failed request); the first, with stderr, wins.
        if case .failed = status { return }
        let stderr = process?.recentStderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        process?.terminate()
        process = nil
        // Agents color their logs for a terminal; the status is shown as plain text.
        status = .failed((stderr.isEmpty ? message : "\(message)\n\n\(stderr)").withoutTerminalEscapes)
    }

    /// Whether the command resolves the way `AgentProcess` will run it: an absolute path, or a name
    /// on the environment's PATH.
    private static func isInstalled(_ command: AgentCommand) -> Bool {
        let fileManager = FileManager.default
        if command.executable.hasPrefix("/") {
            return fileManager.isExecutableFile(atPath: command.executable)
        }
        return command.environment["PATH", default: ""].split(separator: ":").contains { directory in
            fileManager.isExecutableFile(atPath: URL(filePath: String(directory)).appending(path: command.executable).path(percentEncoded: false))
        }
    }

    private static var clientInfo: Implementation {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return Implementation(name: "native", title: "Native", version: version)
    }
}
