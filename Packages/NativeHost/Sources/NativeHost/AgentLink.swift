import ACP
import Foundation
import NativeHostProtocol

/// One agent's process and connection inside the host. Many sessions share it.
@HostActor
final class AgentLink {
    enum Status: Equatable {
        /// Not running: never started, stopped on purpose, or exited on its own (it starts again
        /// when something needs it).
        case stopped
        case starting
        case ready
        /// The launch or `initialize` failed; the message ends with what the agent logged.
        case failed(String)
        case notInstalled(command: String)
    }

    var spec: AgentSpec
    private(set) var status = Status.stopped {
        didSet { if status != oldValue { onChange?() } }
    }
    private(set) var peer: JSONRPCPeer?
    /// The agent's `initialize` result, verbatim, while it runs.
    private(set) var initializeResult: JSONValue?
    private(set) var capabilities: AgentCapabilities?
    /// The spec the running process was started from.
    private(set) var launchedSpec: AgentSpec?
    /// When the running process became ready, for unloading an agent nothing used since.
    private(set) var readyAt = Date.distantPast
    /// The agent turned a request away until the user signs in.
    var needsSignIn = false {
        didSet { if needsSignIn != oldValue { onChange?() } }
    }
    var isSigningIn = false {
        didSet { if isSigningIn != oldValue { onChange?() } }
    }
    /// Its sign-in methods, status, saved keys and a sign-in waiting on the user
    /// (HostCore+Credentials.swift).
    var signIn = AgentSignInState() {
        didSet { if signIn != oldValue { onChange?() } }
    }
    /// Told whenever what `HostAgent` shows changes.
    var onChange: (() -> Void)?
    /// Bumped whenever the process is replaced, so events from an old one are dropped.
    private(set) var generation = 0
    /// Set while the host stops the agent on purpose, so its exit isn't treated as a crash.
    var isStopping = false
    /// The agent answered its rename command with a model's turn, so the host stops naming sessions
    /// with it (`HostCore+AgentNames.swift`).
    var renameAsksModel = false
    /// Why the host is ending the process, when it's one (a restart): recovery says so.
    var exitCause: RecoveryNote.Cause?
    /// Host sessions by the agent's id for them, for routing what the agent sends.
    var routes: [SessionID: HostSessionID] = [:]
    /// Updates for agent sessions the host doesn't know yet: an agent may send them before it
    /// answers `session/new`, or for a subagent it hasn't announced.
    var buffered: [SessionID: [AgentUpdate]] = [:]

    private var process: Process?
    private var processGroups = AgentProcessGroups()
    private var commandProcesses: AgentStopProcesses?
    /// A Stop retains this generation's tree even if the adapter exits during cancel.
    var commandStopOwnsTree = false
    private var stderr = StderrTail()
    private var starting: Task<Void, any Error>?

    private static let bufferLimit = 2_000

    init(spec: AgentSpec) {
        self.spec = spec
    }

    var supportsSteering: Bool {
        capabilities?.steering == true
    }

    var canLoadSessions: Bool {
        capabilities?.loadSession == true
    }

    var processIdentifier: Int32? {
        process?.processIdentifier
    }

    var hostAgent: HostAgent {
        let (state, problem): (HostAgentState, String?) =
            switch status {
            case .stopped: (.stopped, nil)
            case .starting: (.starting, nil)
            case .ready: (.ready, nil)
            case .failed(let message): (.failed, message)
            case .notInstalled(let command): (.notInstalled, command)
            }
        return HostAgent(
            id: spec.id, name: spec.name, state: state, problem: problem,
            initialize: status == .ready ? initializeResult : nil, processID: processIdentifier,
            launchedSpec: status == .ready ? launchedSpec : nil, needsSignIn: needsSignIn, isSigningIn: isSigningIn,
            authMethods: signIn.authMethods(declared: spec.authMethods), signInLink: signIn.link?.shown,
            authStatus: signIn.status, savedCredentials: signIn.savedCredentials)
    }

    /// Launches the agent if it isn't running and waits until it's initialized. Concurrent callers
    /// share one launch. `admit` is asked right before the process spawns, in the same actor turn,
    /// so nothing that revoked the launch while its environment was read can slip in between.
    func ensureStarted(
        environment: @escaping @Sendable () async -> [String: String],
        clientInfo: Implementation,
        admit: @escaping @HostActor () throws -> Void = {},
        onEvent: @escaping @Sendable (Int, JSONRPCPeer.Event) async -> Void
    ) async throws {
        // Keep direct launch callers fail-closed too, before reading any inherited environment.
        try HostAgentRouteAdmission.check(spec, policy: .unrestricted)
        try await waitForCommandStop()
        if status == .ready { return }
        if let starting {
            return try await starting.value
        }
        generation += 1
        let generation = generation
        let spec = spec
        let advertisesLinks = signIn.advertisesLinks
        status = .starting
        needsSignIn = false
        let onExit: @Sendable () -> Void = { [weak self] in
            Task { @HostActor in self?.launcherExited(generation: generation) }
        }
        let task = Task {
            let command = AgentLaunch.command(for: spec, environment: await environment())
            // Ended while its environment was read (`noteExit`): this launch is over, even if the
            // agent may start again by now; that's a launch of its own.
            guard generation == self.generation else { throw PeerError.closed }
            try admit()
            guard AgentLaunch.isInstalled(command) else {
                throw AgentLaunch.Failure.notInstalled(command.executable)
            }
            let (process, channel, stderr) = try AgentLaunch.spawn(command, onExit: onExit)
            self.process = process
            commandProcesses = AgentStopProcesses(root: process.processIdentifier)
            commandStopOwnsTree = false
            self.stderr = stderr
            processGroups = AgentProcessGroups()
            processGroups.note(treeOf: process.processIdentifier)
            let peer = JSONRPCPeer(channel: channel, label: spec.id) { event in await onEvent(generation, event) }
            self.peer = peer
            peer.start()
            let result = try await peer.request(
                "initialize", HostInitializeRequest(clientInfo: clientInfo, advertisesLinks: advertisesLinks),
                as: JSONValue.self)
            let response = try JSONDecoder().decode(InitializeResponse.self, from: JSONEncoder().encode(result))
            guard response.protocolVersion == ACP.protocolVersion else {
                throw AgentLaunch.Failure.incompatible(name: spec.name, version: response.protocolVersion)
            }
            initializeResult = result
            signIn.advertised = response.authMethods
            capabilities = response.agentCapabilities
            launchedSpec = spec
            // By now a launcher has started the agent proper, in whatever group it chose.
            processGroups.note(treeOf: process.processIdentifier)
            commandProcesses?.refresh()
        }
        starting = task
        defer { if generation == self.generation { starting = nil } }
        do {
            try await task.value
            guard generation == self.generation else { throw PeerError.closed }
            readyAt = .now
            status = .ready
        } catch {
            guard generation == self.generation else { throw error }
            terminateProcess()
            peer = nil
            if case AgentLaunch.Failure.notInstalled(let command) = error {
                status = .notInstalled(command: command)
                throw error
            }
            let message = startupFailure(error.localizedDescription)
            status = .failed(message)
            throw AgentLaunch.Failure.startFailed(message)
        }
    }

    /// Forgets the process after it exited (or the host ended it); returns false for an event from
    /// a process already replaced.
    func noteExit(generation: Int) -> Bool {
        guard generation == self.generation, status == .ready || status == .starting else { return false }
        // Exiting during initialize is a failed launch, not an idle agent. Advancing the
        // generation makes ensureStarted discard its result, so preserve the failure here.
        let nextStatus: Status =
            status == .starting && !isStopping
            ? .failed(startupFailure("The process exited before initialization finished.")) : .stopped
        self.generation += 1
        starting = nil
        isStopping = false
        peer?.close()
        peer = nil
        initializeResult = nil
        terminateProcess()
        routes = [:]
        buffered = [:]
        status = nextStatus
        return true
    }

    private func startupFailure(_ reason: String) -> String {
        let detail = recentStderr
        let message = "\(spec.name) couldn't start. Choose Restart to try again.\n\n\(reason)"
        return detail.isEmpty ? message : "\(message)\n\n\(detail.suffix(2_000))"
    }

    /// The end of what the agent logged, for saying why it stopped.
    var recentStderr: String {
        stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Ends the process: on purpose (`isStopping`, so its exit isn't a crash), or for `cause`. The
    /// caller follows with `HostCore.agentExited`.
    func end(cause: RecoveryNote.Cause? = nil) {
        isStopping = cause == nil
        exitCause = cause
        peer?.close()
        terminateProcess()
    }

    /// For a host about to exit: ends every process the agent started before returning.
    func endNow() {
        isStopping = true
        if let process, process.isRunning { processGroups.note(treeOf: process.processIdentifier) }
        peer?.close()
        processGroups.endNow()
        process = nil
    }

    /// The stop cleanup owns this tree from here. Exit callbacks must not schedule additional
    /// group signals, which could arrive after cleanup and reach a reused group id.
    func beginCommandStop() {
        isStopping = true
        process = nil
        processGroups = AgentProcessGroups()
    }

    /// Keep the launch identity: a pid read for the first time at Stop might already be reused.
    func processesForStop() -> AgentStopProcesses? {
        commandProcesses?.refresh()
        return commandProcesses
    }

    /// New work waits for the frozen generation to exit, then loads on its replacement.
    func waitForCommandStop() async throws {
        while commandStopOwnsTree {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    func commandsDidStop() {
        beginCommandStop()
        commandProcesses = nil
        commandStopOwnsTree = false
        isStopping = false
        peer?.close()
    }

    func buffer(_ update: AgentUpdate, for session: SessionID) {
        guard buffered[session, default: []].count < Self.bufferLimit else { return }
        buffered[session, default: []].append(update)
    }

    /// The launched process exited. If it was a launcher whose agent lives on holding the pipes,
    /// the agent is ended too, so the session recovers instead of talking to an orphan.
    private func launcherExited(generation: Int) {
        guard generation == self.generation, !isStopping, !commandStopOwnsTree else { return }
        processGroups.end()
    }

    private func terminateProcess() {
        if commandStopOwnsTree {
            processGroups = AgentProcessGroups()
            process = nil
            return
        }
        if let pid = process?.processIdentifier, process?.isRunning == true {
            processGroups.note(treeOf: pid)
        }
        processGroups.end()
        process = nil
    }
}

/// Turning an `AgentSpec` into a running process.
enum AgentLaunch {
    enum Failure: Error, LocalizedError {
        case notInstalled(String)
        case incompatible(name: String, version: Int)
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled(let command): "\(command) isn't installed or isn't on your PATH."
            case .incompatible(let name, let version):
                "\(name) speaks ACP version \(version); Native supports version \(ACP.protocolVersion)."
            case .startFailed(let message): message
            }
        }

        var rpcError: RPCError {
            let code: HostErrorCode =
                switch self {
                case .notInstalled: .agentNotInstalled
                case .incompatible, .startFailed: .agentUnavailable
                }
            return code.rpcError(errorDescription ?? "The agent couldn't start.")
        }
    }

    /// The command for `spec`, without npm in the middle when npx has the exact version installed
    /// (`AgentCommand.skippingNpx`).
    static func command(for spec: AgentSpec, environment: [String: String]) -> AgentCommand {
        var environment = environment.merging(spec.env) { $1 }
        for (variable, executable) in spec.resolveExecutables {
            if let path = executablePath(executable, in: environment) {
                environment[variable] = path
            }
        }
        return AgentCommand(
            executable: spec.command, arguments: spec.args, environment: environment,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        ).skippingNpx()
    }

    static func isInstalled(_ command: AgentCommand) -> Bool {
        if command.executable.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command.executable)
        }
        return executablePath(command.executable, in: command.environment) != nil
    }

    /// Starts the agent with its stdio piped to us. `env` resolves the command against the PATH we
    /// hand it, which a launchd job's own PATH lacks.
    static func spawn(
        _ command: AgentCommand, onExit: @escaping @Sendable () -> Void
    ) throws -> (Process, ByteChannel, StderrTail) {
        let process = Process()
        process.terminationHandler = { _ in onExit() }
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [command.executable] + command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        let stdin = closeOnExecPipe()
        let stdout = closeOnExecPipe()
        let stderrPipe = closeOnExecPipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderrPipe
        // The tail and the channel get their own copies of our ends; closing the originals means that
        // when the channel closes stdin, the agent sees EOF. Close-on-exec copies, like the pipes.
        let stderr = try StderrTail(reading: fcntl(stderrPipe.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 0))
        try process.run()
        let channel = ByteChannel(
            reading: fcntl(stdout.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 0),
            writing: fcntl(stdin.fileHandleForWriting.fileDescriptor, F_DUPFD_CLOEXEC, 0),
            label: command.executable
        )
        try? stdout.fileHandleForReading.close()
        try? stdin.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForReading.close()
        return (process, channel, stderr)
    }

    /// A pipe whose descriptors are close-on-exec, so no process this one starts by other means than
    /// `Process` inherits an end and holds it open: an agent would never see the end of its input.
    /// `Process` passes the agent its ends explicitly, so they still arrive.
    private static func closeOnExecPipe() -> Pipe {
        let pipe = Pipe()
        for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
            _ = fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC)
        }
        return pipe
    }

    private static func executablePath(_ name: String, in environment: [String: String]) -> String? {
        environment["PATH", default: ""].split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: name).path(percentEncoded: false) }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
