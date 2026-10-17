import Foundation

/// Why a git command failed, in terms a person can act on. Read from git's own messages, which are
/// stable across versions for these cases; anything unrecognized is `.other`.
public enum GitFailure: Hashable, Sendable {
    /// The remote has commits the branch doesn't; pull, then push again.
    case pushRejected
    /// The branch and its upstream have both moved, and git wasn't told to merge or rebase.
    case divergentBranches
    /// The remote refused the push: a protected branch or a server-side hook.
    case remoteRefused
    /// The credentials or SSH key were rejected or missing.
    case authenticationFailed
    /// The remote couldn't be reached.
    case networkUnavailable
    case noRemote
    case detachedHead
    /// Unresolved conflicts block the commit.
    case unmergedFiles
    /// The selected changes add up to nothing to commit.
    case nothingToCommit
    /// A commit hook (pre-commit, commit-msg) stopped the commit; its output says why.
    case hookFailed
    /// Another git process holds the repository's lock.
    case repositoryLocked
    /// A pull would overwrite uncommitted changes.
    case localChangesWouldBeOverwritten
    /// The merge or rebase from a pull stopped on conflicts.
    case conflicts
    case other
}

extension GitError {
    public var failure: GitFailure {
        switch self {
        case .noRemote: return .noRemote
        case .detachedHead: return .detachedHead
        case .gitNotFound, .launchFailed, .unexpectedOutput, .cancelled: return .other
        case .failed(let arguments, _, let stderr):
            return Self.classify(command: arguments.first ?? "", output: stderr.lowercased())
        }
    }

    static func classify(command: String, output: String) -> GitFailure {
        let has = { (needles: [String]) in needles.contains { output.contains($0) } }
        if has(["index.lock", "another git process seems to be running"]) { return .repositoryLocked }
        if has(["could not resolve host", "could not connect", "connection timed out", "network is unreachable", "connection refused", "unable to access", "operation timed out"]) {
            // "unable to access" also wraps authentication failures over HTTPS.
            if has(["403", "401", "authentication"]) { return .authenticationFailed }
            return .networkUnavailable
        }
        if has(["authentication failed", "permission denied (publickey", "could not read username", "could not read password", "terminal prompts disabled", "invalid username or password", "host key verification failed"]) {
            return .authenticationFailed
        }
        if has(["divergent branches", "need to specify how to reconcile"]) { return .divergentBranches }
        if has(["would be overwritten by merge", "would be overwritten by checkout", "please commit your changes or stash them"]) { return .localChangesWouldBeOverwritten }
        if has(["protected branch", "pre-receive hook declined", "remote rejected", "push declined"]) { return .remoteRefused }
        if has(["non-fast-forward", "fetch first", "updates were rejected"]) { return .pushRejected }
        if has(["unmerged files", "you have unmerged paths", "not possible because you have unmerged"]) { return .unmergedFiles }
        if command == "pull", has(["conflict"]) { return .conflicts }
        if has(["nothing to commit", "nothing added to commit", "no changes added to commit"]) { return .nothingToCommit }
        if has(["no configured push destination", "does not appear to be a git repository", "no such remote"]) { return .noRemote }
        // A commit that fails for any other reason after git starts it is a hook saying no.
        if command == "commit" { return .hookFailed }
        return .other
    }
}
