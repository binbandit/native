import Foundation

/// How a project's setup script went in a new worktree.
public struct SetupScriptResult: Hashable, Sendable {
    /// `nil` when the script was stopped for running too long.
    public var exitCode: Int32?
    /// Standard output, then standard error.
    public var output: String
    public var duration: Duration

    public init(exitCode: Int32?, output: String, duration: Duration) {
        self.exitCode = exitCode
        self.output = output
        self.duration = duration
    }

    public var succeeded: Bool { exitCode == 0 }
    public var timedOut: Bool { exitCode == nil }
}
