import Foundation

/// A remote as `git remote -v` lists it.
public struct Remote: Hashable, Sendable {
    public var name: String
    /// Where it fetches from, after the user's `insteadOf` rewrites.
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

// Remotes, fetching from them and tracking their branches: what checking out someone else's branch
// (a pull request's head) takes. `fetch` talks to the network, so it only runs when the user asks.
extension Repository {
    /// The configured remotes with their fetch URLs, in git's order.
    public func remoteURLs() async throws(GitError) -> [Remote] {
        let output = try await run(["remote", "-v"], readOnly: true)
        let suffix = " (fetch)"
        return output.text.split(separator: "\n").compactMap { line in
            guard line.hasSuffix(suffix) else { return nil }
            let parts = line.dropLast(suffix.count).split(separator: "\t", maxSplits: 1)
            return parts.count == 2 ? Remote(name: String(parts[0]), url: String(parts[1])) : nil
        }
    }

    public func addRemote(_ name: String, url: String) async throws(GitError) {
        try await run(["remote", "add", name, url])
    }

    public func removeRemote(_ name: String) async throws(GitError) {
        try await run(["remote", "remove", name])
    }

    /// Fetches `refspecs` from `remote`, a remote's name or a URL, without its tags.
    public func fetch(from remote: String, refspecs: [String]) async throws(GitError) {
        try await run(["fetch", "--no-tags", remote] + refspecs)
    }

    /// Creates `name` at `startPoint` without checking it out or tracking anything.
    public func createBranch(_ name: String, at startPoint: String) async throws(GitError) {
        try await run(["branch", "--no-track", name, startPoint])
    }

    /// Deletes a branch Native just made and nothing else uses, e.g. after a step that followed it
    /// failed. Branches with work on them are archived instead (`archiveBranch`).
    public func deleteBranch(_ name: String) async throws(GitError) {
        try await run(["branch", "--delete", "--force", name])
    }

    /// Makes `branch` pull from, and push to, `remoteBranch` on `remote`, which may have another
    /// name. Set directly rather than with `--track`, which needs the remote's fetch refspec to
    /// cover the branch (a single-branch clone's doesn't).
    public func setUpstream(of branch: String, remote: String, remoteBranch: String) async throws(GitError) {
        try await run(["config", "branch.\(branch).remote", remote])
        try await run(["config", "branch.\(branch).merge", "refs/heads/\(remoteBranch)"])
    }

    /// Whether the repository has `commit` at all.
    public func hasCommit(_ commit: String) async throws(GitError) -> Bool {
        try await resolve("\(commit)^{commit}") != nil
    }

    /// Whether `commit` is in the history of `revision`.
    public func contains(_ commit: String, in revision: String = "HEAD") async throws(GitError) -> Bool {
        let output = try await run(
            ["merge-base", "--is-ancestor", commit, revision], readOnly: true, acceptingStatus: [0, 1])
        return output.status == 0
    }

    /// Moves the checked-out branch forward to `revision`. Fails, changing nothing, when that isn't
    /// a fast-forward or would overwrite uncommitted changes.
    public func fastForward(to revision: String) async throws(GitError) {
        try await run(["merge", "--ff-only", revision])
    }

    // MARK: - Branch notes

    /// Keeps `value` with `branch` in the repository's config (`branch.<name>.<key>`), where
    /// `git branch -m` carries it along and deleting the branch removes it.
    public func setNote(_ key: String, _ value: String, on branch: String) async throws(GitError) {
        try await run(["config", "branch.\(branch).\(key)", value])
    }

    /// Every branch's value for `key`, by branch name. Keys ignore case, as git's do.
    public func notes(_ key: String) async throws(GitError) -> [String: String] {
        let output = try await run(
            ["config", "--null", "--get-regexp", #"^branch\..*\."# + NSRegularExpression.escapedPattern(for: key) + "$"],
            readOnly: true, acceptingStatus: [0, 1])
        let suffix = "." + key.lowercased()
        var notes: [String: String] = [:]
        // `--null`: each entry is `name\nvalue\0`.
        for entry in output.text.split(separator: "\0") {
            let parts = entry.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].hasPrefix("branch."), parts[0].lowercased().hasSuffix(suffix) else {
                continue
            }
            // Branch names may contain dots, so only the prefix and the key come off.
            let name = parts[0].dropFirst("branch.".count).dropLast(suffix.count)
            notes[String(name)] = String(parts[1])
        }
        return notes
    }
}
