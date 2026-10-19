import Foundation

/// Runs a command to completion on some machine: this Mac today, a remote Native Host later. Code
/// that shells out (git, gh, MCP probes) takes a runner instead of starting processes itself, so the
/// same code works wherever the project lives.
public protocol CommandRunner: Sendable {
    func run(_ command: Command) async throws -> CommandResult
    /// Runs like `run(_:)`, handing over output as it arrives, for showing a long command's
    /// progress. Output already handed over stays handed over when the command then times out.
    func run(_ command: Command, onOutput: @escaping @Sendable (CommandOutput) -> Void) async throws -> CommandResult
}

extension CommandRunner {
    /// For runners that can't stream: all the output at once, when the command ends.
    public func run(
        _ command: Command, onOutput: @escaping @Sendable (CommandOutput) -> Void
    ) async throws -> CommandResult {
        let result = try await run(command)
        if !result.standardOutput.isEmpty {
            onOutput(CommandOutput(stream: .standardOutput, data: result.standardOutput))
        }
        if !result.standardError.isEmpty {
            onOutput(CommandOutput(stream: .standardError, data: result.standardError))
        }
        return result
    }
}

/// A piece of a command's output, as it arrived.
public struct CommandOutput: Hashable, Sendable {
    public enum Stream: Hashable, Sendable {
        case standardOutput, standardError
    }

    public var stream: Stream
    public var data: Data

    public init(stream: Stream, data: Data) {
        self.stream = stream
        self.data = data
    }
}

/// One command invocation. `executable` is a name looked up on `environment`'s PATH, or an absolute
/// path on the machine that runs it.
public struct Command: Hashable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var directory: String?
    /// The complete environment. Callers pass the user's login-shell environment, since GUI apps
    /// (and remote hosts) don't inherit a terminal's.
    public var environment: [String: String]
    public var standardInput: Data?
    /// Kills the command, and everything it started, after this long; nil waits as long as it takes.
    public var timeout: Duration?
    /// Whether the command is done when it exits, rather than once everything it started has closed
    /// its output: for scripts that leave a server running in the background. That output is still
    /// read, so the server never blocks on a full pipe, but dropped.
    public var outputEndsAtExit: Bool

    public init(
        _ executable: String,
        _ arguments: [String] = [],
        in directory: String? = nil,
        environment: [String: String],
        standardInput: Data? = nil,
        timeout: Duration? = nil,
        outputEndsAtExit: Bool = false
    ) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.standardInput = standardInput
        self.timeout = timeout
        self.outputEndsAtExit = outputEndsAtExit
    }
}

public struct CommandResult: Hashable, Sendable {
    public var exitCode: Int32
    public var standardOutput: Data
    public var standardError: Data

    public init(exitCode: Int32, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { exitCode == 0 }
    public var output: String { String(decoding: standardOutput, as: UTF8.self) }
    public var errorOutput: String { String(decoding: standardError, as: UTF8.self) }
}

public enum CommandError: Error, Hashable, Sendable, LocalizedError {
    /// The executable isn't on the PATH, or doesn't exist, on the machine that tried to run it.
    case notFound(String)
    case timedOut(String, after: Duration)
    /// The runner couldn't reach its machine (a remote host that's offline, for example).
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let executable): "\(executable) isn't installed or isn't on the PATH."
        case .timedOut(let executable, let duration): "\(executable) didn't finish within \(duration)."
        case .unavailable(let reason): reason
        }
    }
}
