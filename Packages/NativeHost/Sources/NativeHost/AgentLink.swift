import ACP
import Foundation
import NativeHostProtocol
import Synchronization

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
    /// The agent turned a request away until the user signs in.
    var needsSignIn = false {
        didSet { if needsSignIn != oldValue { onChange?() } }
    }
    var isSigningIn = false {
        didSet { if isSigningIn != oldValue { onChange?() } }
    }
    /// Told whenever what `HostAgent` shows changes.
    var onChange: (() -> Void)?
    /// Bumped whenever the process is replaced, so events from an old one are dropped.
    private(set) var generation = 0
    /// Set while the host stops the agent on purpose, so its exit isn't treated as a crash.
    var isStopping = false
    /// Why the host is ending the process, when it's one (a restart): recovery says so.
    var exitCause: RecoveryNote.Cause?
    /// Host sessions by the agent's id for them, for routing what the agent sends.
    var routes: [SessionID: HostSessionID] = [:]
    /// Updates for agent sessions the host doesn't know yet: an agent may send them before it
    /// answers `session/new`, or for a subagent it hasn't announced.
    var buffered: [SessionID: [AgentUpdate]] = [:]

    private var process: Process?
    private var processGroups = AgentProcessGroups()
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
            launchedSpec: status == .ready ? launchedSpec : nil, needsSignIn: needsSignIn, isSigningIn: isSigningIn)
    }

    /// Launches the agent if it isn't running and waits until it's initialized. Concurrent callers
    /// share one launch.
    func ensureStarted(
        environment: @escaping @Sendable () async -> [String: String],
        clientInfo: Implementation,
        onEvent: @escaping @Sendable (Int, JSONRPCPeer.Event) async -> Void
    ) async throws {
        if status == .ready { return }
        if let starting {
            return try await starting.value
        }
        generation += 1
        let generation = generation
        let spec = spec
        status = .starting
        needsSignIn = false
        let onExit: @Sendable () -> Void = { [weak self] in
            Task { @HostActor in self?.launcherExited(generation: generation) }
        }
        let task = Task {
            let command = AgentLaunch.command(for: spec, environment: await environment())
            guard AgentLaunch.isInstalled(command) else {
                throw AgentLaunch.Failure.notInstalled(command.executable)
            }
            let (process, channel, stderr) = try AgentLaunch.spawn(command, onExit: onExit)
            self.process = process
            self.stderr = stderr
            processGroups = AgentProcessGroups()
            processGroups.note(treeOf: process.processIdentifier)
            let peer = JSONRPCPeer(channel: channel, label: spec.id) { event in await onEvent(generation, event) }
            self.peer = peer
            peer.start()
            let result = try await peer.request(
                "initialize", HostInitializeRequest(clientInfo: clientInfo), as: JSONValue.self)
            let response = try JSONDecoder().decode(InitializeResponse.self, from: JSONEncoder().encode(result))
            guard response.protocolVersion == ACP.protocolVersion else {
                throw AgentLaunch.Failure.incompatible(name: spec.name, version: response.protocolVersion)
            }
            initializeResult = result
            capabilities = response.agentCapabilities
            launchedSpec = spec
            // By now a launcher has started the agent proper, in whatever group it chose.
            processGroups.note(treeOf: process.processIdentifier)
        }
        starting = task
        defer { starting = nil }
        do {
            try await task.value
            guard generation == self.generation else { throw PeerError.closed }
            status = .ready
        } catch {
            guard generation == self.generation else { throw error }
            terminateProcess()
            peer = nil
            if case AgentLaunch.Failure.notInstalled(let command) = error {
                status = .notInstalled(command: command)
                throw error
            }
            let detail = stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let message =
                detail.isEmpty ? error.localizedDescription : "\(error.localizedDescription)\n\n\(detail.suffix(2_000))"
            status = .failed(message)
            throw AgentLaunch.Failure.startFailed(message)
        }
    }

    /// Forgets the process after it exited (or the host ended it); returns false for an event from
    /// a process already replaced.
    func noteExit(generation: Int) -> Bool {
        guard generation == self.generation, status == .ready || status == .starting else { return false }
        self.generation += 1
        isStopping = false
        status = .stopped
        peer?.close()
        peer = nil
        initializeResult = nil
        terminateProcess()
        routes = [:]
        buffered = [:]
        return true
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
        peer?.close()
        processGroups.endNow()
        process = nil
    }

    func buffer(_ update: AgentUpdate, for session: SessionID) {
        guard buffered[session, default: []].count < Self.bufferLimit else { return }
        buffered[session, default: []].append(update)
    }

    /// The launched process exited. If it was a launcher whose agent lives on holding the pipes,
    /// the agent is ended too, so the session recovers instead of talking to an orphan.
    private func launcherExited(generation: Int) {
        guard generation == self.generation, !isStopping else { return }
        processGroups.end()
    }

    private func terminateProcess() {
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
        let stderr = StderrTail()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderr.append(data)
            }
        }
        try process.run()
        // The channel gets its own copies of our ends; closing the originals means that when the
        // channel closes stdin, the agent sees EOF. Close-on-exec copies, like the pipes themselves.
        let channel = ByteChannel(
            reading: fcntl(stdout.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 0),
            writing: fcntl(stdin.fileHandleForWriting.fileDescriptor, F_DUPFD_CLOEXEC, 0),
            label: command.executable
        )
        try? stdout.fileHandleForReading.close()
        try? stdin.fileHandleForWriting.close()
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

/// The last few KB of an agent's stderr, for explaining why it failed.
final class StderrTail: Sendable {
    private static let limit = 16 * 1024
    private let buffer = Mutex(Data())

    func append(_ data: Data) {
        buffer.withLock { buffer in
            buffer.append(data)
            if buffer.count > Self.limit {
                buffer.removeFirst(buffer.count - Self.limit)
            }
        }
    }

    var text: String {
        buffer.withLock { String(decoding: $0, as: UTF8.self) }
    }
}
