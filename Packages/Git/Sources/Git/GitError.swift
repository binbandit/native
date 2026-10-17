import Foundation

/// A failure running git. Failed commands carry what git printed, which is usually the best
/// explanation there is: a hook's output, a rejected push, a missing identity.
public enum GitError: Error, Sendable, Equatable {
    /// No `git` executable was found on the supplied PATH.
    case gitNotFound
    /// The git process couldn't be started.
    case launchFailed(String)
    /// git ran and exited unsuccessfully.
    case failed(arguments: [String], status: Int32, stderr: String)
    /// git's output didn't have the expected shape.
    case unexpectedOutput(String)
    /// Pushing needs a branch, and HEAD is detached.
    case detachedHead
    /// There's no remote to push to.
    case noRemote
    /// The task running the command was cancelled.
    case cancelled
}

extension GitError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .gitNotFound:
            "Git isn't installed, or isn't on your shell's PATH."
        case .launchFailed(let reason):
            "Couldn't run git: \(reason)"
        case .failed(let arguments, let status, let stderr):
            stderr.isEmpty ? "git \(arguments.first ?? "") failed with exit code \(status)." : Self.summarize(stderr)
        case .unexpectedOutput(let detail):
            "git printed something unexpected: \(detail)"
        case .detachedHead:
            "HEAD is detached. Check out a branch to push."
        case .noRemote:
            "This repository has no remote to push to."
        case .cancelled:
            "The git command was cancelled."
        }
    }

    /// git's message without its `fatal:`/`error:` prefixes and the hint lines around it.
    static func summarize(_ stderr: String) -> String {
        let lines =
            stderr
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("hint:") }
        let cleaned = lines.map { line in
            for prefix in ["fatal: ", "error: "] where line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
            return line
        }
        return cleaned.isEmpty
            ? stderr.trimmingCharacters(in: .whitespacesAndNewlines) : cleaned.joined(separator: "\n")
    }
}
