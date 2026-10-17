import ACP
import Foundation
import NativeHostProtocol
import Synchronization

/// One agent's process and connection inside the host. Many sessions share it.
@HostActor
final class AgentLink {
    enum Status: Equatable {
        case stopped
        case starting
        case ready
        case failed(String)
    }

    var spec: AgentSpec
    private(set) var status = Status.stopped
    private(set) var peer: JSONRPCPeer?
    private(set) var supportsSteering = false
    private(set) var canLoadSessions = false
    /// Bumped whenever the process is replaced, so events from an old one are dropped.
    private(set) var generation = 0
    /// Set while the host stops the agent on purpose, so its exit isn't treated as a crash.
    var isStopping = false
    /// Host sessions by the agent's id for them, for routing what the agent sends.
    var routes: [SessionID: HostSessionID] = [:]
    /// Updates for agent sessions the host doesn't know yet: an agent may send them before it
    /// answers `session/new`, or for a subagent it hasn't announced.
    var buffered: [SessionID: [JSONValue]] = [:]

    private var process: Process?
    private var stderr = StderrTail()
    private var starting: Task<Void, any Error>?

    private static let bufferLimit = 2_000

    init(spec: AgentSpec) {
        self.spec = spec
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
        status = .starting
        let task = Task {
            let command = AgentLaunch.command(for: spec, environment: await environment())
            guard AgentLaunch.isInstalled(command) else {
                throw AgentLaunch.Failure.notInstalled(command.executable)
            }
            let (process, channel, stderr) = try AgentLaunch.spawn(command)
            self.process = process
            self.stderr = stderr
            let peer = JSONRPCPeer(channel: channel, label: spec.id) { event in await onEvent(generation, event) }
            self.peer = peer
            peer.start()
            let response = try await peer.request("initialize", HostInitializeRequest(clientInfo: clientInfo), as: HostInitializeResponse.self)
            guard response.protocolVersion == ACP.protocolVersion else {
                throw AgentLaunch.Failure.incompatible(name: spec.name, version: response.protocolVersion)
            }
            supportsSteering = response.supportsSteering
            canLoadSessions = response.agentCapabilities?.loadSession == true
        }
        starting = task
        defer { starting = nil }
        do {
            try await task.value
            guard generation == self.generation else { throw PeerError.closed }
            status = .ready
        } catch {
            guard generation == self.generation else { throw error }
            let detail = stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? error.localizedDescription : "\(error.localizedDescription)\n\n\(detail.suffix(2_000))"
            terminateProcess()
            status = .failed(message)
            throw AgentLaunch.Failure.startFailed(message)
        }
    }

    /// Forgets the process after it exited; returns false for an event from a process already replaced.
    func noteExit(generation: Int) -> Bool {
        guard generation == self.generation, status != .stopped else { return false }
        self.generation += 1
        let stderr = stderr.text.trimmingCharacters(in: .whitespacesAndNewlines)
        status = isStopping ? .stopped : .failed(stderr.isEmpty ? "\(spec.name) exited." : "\(spec.name) exited.\n\n\(stderr.suffix(2_000))")
        isStopping = false
        peer = nil
        terminateProcess()
        routes = [:]
        buffered = [:]
        return true
    }

    /// Stops the agent on purpose.
    func stop() {
        isStopping = true
        peer?.close()
        terminateProcess()
    }

    func buffer(_ update: JSONValue, for session: SessionID) {
        guard buffered[session, default: []].count < Self.bufferLimit else { return }
        buffered[session, default: []].append(update)
    }

    var processIdentifier: Int32? {
        process?.processIdentifier
    }

    private func terminateProcess() {
        if let process, process.isRunning {
            process.terminate()
        }
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
            case .incompatible(let name, let version): "\(name) speaks ACP version \(version); Native supports version \(ACP.protocolVersion)."
            case .startFailed(let message): message
            }
        }
    }

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
        )
    }

    static func isInstalled(_ command: AgentCommand) -> Bool {
        if command.executable.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command.executable)
        }
        return executablePath(command.executable, in: command.environment) != nil
    }

    /// Starts the agent with its stdio piped to us. `env` resolves the command against the PATH we
    /// hand it, which a launchd job's own PATH lacks.
    static func spawn(_ command: AgentCommand) throws -> (Process, ByteChannel, StderrTail) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = [command.executable] + command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        let stdin = Pipe()
        let stdout = Pipe()
        let stderrPipe = Pipe()
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
        // channel closes stdin, the agent sees EOF.
        let channel = ByteChannel(
            reading: dup(stdout.fileHandleForReading.fileDescriptor),
            writing: dup(stdin.fileHandleForWriting.fileDescriptor),
            label: command.executable
        )
        try? stdout.fileHandleForReading.close()
        try? stdin.fileHandleForWriting.close()
        return (process, channel, stderr)
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
