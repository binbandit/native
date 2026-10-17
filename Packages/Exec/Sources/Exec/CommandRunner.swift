import Foundation

/// Runs a command to completion on some machine: this Mac today, a remote Native Host later. Code
/// that shells out (git, gh, MCP probes) takes a runner instead of starting processes itself, so the
/// same code works wherever the project lives.
public protocol CommandRunner: Sendable {
    func run(_ command: Command) async throws -> CommandResult
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
    /// Kills the command after this long; nil waits as long as it takes.
    public var timeout: Duration?

    public init(
        _ executable: String,
        _ arguments: [String] = [],
        in directory: String? = nil,
        environment: [String: String],
        standardInput: Data? = nil,
        timeout: Duration? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.standardInput = standardInput
        self.timeout = timeout
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
