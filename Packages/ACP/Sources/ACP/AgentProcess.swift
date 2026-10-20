// Wherever Foundation can start a process: everywhere but iOS.
#if os(macOS) || os(Linux)
import Foundation
import Synchronization

#if canImport(os)
import os
#endif

/// How to start an agent that speaks ACP over stdio.
public struct AgentCommand: Hashable, Sendable {
    /// A command name looked up on the `PATH` in `environment`, or an absolute path.
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL?

    public init(
        executable: String, arguments: [String] = [], environment: [String: String], workingDirectory: URL? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// A running agent subprocess and the ACP connection to it.
public final class AgentProcess: Sendable {
    public let connection: ACPConnection
    private let process: Process
    private let stderr: StderrTail

    /// Launches the agent and starts reading from it. Events (including `.disconnected` when it
    /// exits) go to `onEvent`.
    public init(_ command: AgentCommand, onEvent: @escaping ACPConnection.EventHandler) throws {
        let process = Process()
        // `env` resolves the command against the PATH we hand it, which a GUI app's own PATH lacks.
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
        self.process = process
        self.stderr = stderr
        self.connection = ACPConnection(
            reading: stdout.fileHandleForReading,
            writing: stdin.fileHandleForWriting,
            onEvent: onEvent
        )
    }

    public func start() async {
        await connection.start()
    }

    /// The launched process (`env`, which execs the agent); its descendants are the agent's own
    /// children. For resource reporting.
    public var processIdentifier: Int32 {
        process.processIdentifier
    }

    /// The end of what the agent logged to stderr, for explaining why it failed.
    public var recentStderr: String {
        stderr.text
    }

    public func terminate() {
        // Closing stdin lets well-behaved agents shut down their own children before we signal.
        try? (process.standardInput as? Pipe)?.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }
}

/// Keeps the last few KB of the agent's stderr and mirrors it to the unified log.
private final class StderrTail: Sendable {
    private static let limit = 16 * 1024
    private let buffer = Mutex(Data())
    private let logger = Logger(subsystem: "Native", category: "AgentStderr")

    func append(_ data: Data) {
        logger.debug("\(String(decoding: data, as: UTF8.self), privacy: .public)")
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
#endif
