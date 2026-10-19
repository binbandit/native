import Foundation

/// How a pull request's head gets into a local checkout, the way `gh pr checkout` does it: from a
/// remote the project already has for the head's repository; from a remote added for a fork the
/// user can push to; otherwise from GitHub's read-only copy of the head on the base repository
/// (`refs/pull/<n>/head`), which works for any fork, even a deleted one.
public struct PullRequestCheckoutPlan: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// The head branch on one of the project's remotes, tracked there.
        case remote(name: String, branch: String)
        /// The head branch in a fork the project has no remote for: added as `name` at `url`, then
        /// tracked there.
        case newRemote(name: String, url: String, branch: String)
        /// GitHub's copy of the head on the base repository, from a remote's name or a URL.
        case pullRef(remote: String, number: Int)
    }

    public var source: Source
    /// The local branch to create, before it's made unique: `pr-78-add-maxlength-option`.
    public var branch: String
    /// GitHub's read-only copy of the head, for when the head's repository can't be fetched (the
    /// fork was deleted or made private, or the branch is gone); `nil` when that's the source
    /// already.
    public var readOnlyFallback: Source?

    /// - Parameters:
    ///   - remotes: The project's remotes.
    ///   - viewer: The signed-in login, which can always push to its own fork.
    ///   - permission: The viewer's permission on the base repository; `nil` when unknown.
    public init(
        _ pullRequest: PullRequestDetails, remotes: [GitRemote], viewer: String?, permission: RepositoryPermission?
    ) {
        branch = PullRequestTaskBranch.name(number: pullRequest.number, title: pullRequest.title)
        let base = pullRequest.baseRepository
        let baseRemote = base.flatMap { Self.remote(for: $0, in: remotes) }
        let readOnly = Source.pullRef(
            remote: baseRemote?.name ?? base?.remoteURL(like: remotes.first?.url) ?? pullRequest.url.absoluteString,
            number: pullRequest.number)
        defer { readOnlyFallback = source == readOnly ? nil : readOnly }
        guard let head = pullRequest.headRepository, !pullRequest.headRefName.isEmpty else {
            source = readOnly
            return
        }
        if let headRemote = Self.remote(for: head, in: remotes) {
            source = .remote(name: headRemote.name, branch: pullRequest.headRefName)
        } else if pullRequest.isCrossRepository,
            Self.canPushToFork(pullRequest, head: head, viewer: viewer, permission: permission)
        {
            source = .newRemote(
                name: Self.newRemoteName(for: head, taken: Set(remotes.map(\.name))),
                url: head.remoteURL(like: baseRemote?.url ?? remotes.first?.url),
                branch: pullRequest.headRefName)
        } else {
            source = readOnly
        }
    }

    public init(source: Source, branch: String, readOnlyFallback: Source? = nil) {
        self.source = source
        self.branch = branch
        self.readOnlyFallback = readOnlyFallback
    }

    /// The same checkout from GitHub's read-only copy of the head.
    public var readOnly: PullRequestCheckoutPlan? {
        readOnlyFallback.map { PullRequestCheckoutPlan(source: $0, branch: branch) }
    }

    /// The remote's name or URL to fetch from.
    public var fetchRemote: String {
        switch source {
        case .remote(let name, _), .newRemote(let name, _, _): name
        case .pullRef(let remote, _): remote
        }
    }

    /// What to fetch. A tracked branch lands in its remote-tracking ref; a pull ref straight in
    /// `localBranch`, as `gh pr checkout` does, so nothing else in the repository changes.
    public func fetchRefspec(into localBranch: String) -> String {
        switch source {
        case .remote(let name, let branch), .newRemote(let name, _, let branch):
            "+refs/heads/\(branch):refs/remotes/\(name)/\(branch)"
        case .pullRef(_, let number):
            "refs/pull/\(number)/head:refs/heads/\(localBranch)"
        }
    }

    /// The remote-tracking branch the local branch starts from and tracks; `nil` for a pull ref,
    /// which has nothing to track.
    public var upstream: (remote: String, branch: String)? {
        switch source {
        case .remote(let name, let branch), .newRemote(let name, _, let branch): (name, branch)
        case .pullRef: nil
        }
    }

    /// What pushes to the pull request from a checkout on `localBranch`: the names differ, so it
    /// names the head branch (git's default `push.default=simple` refuses a bare `git push`).
    /// `nil` when there's nowhere to push.
    public var pushCommand: String? {
        upstream.map { "git push \($0.remote) HEAD:\($0.branch)" }
    }

    // MARK: - Helpers

    /// The remote that best matches `repository`: an exact match over an SSH alias, and among
    /// equals `upstream`, then `origin`, then the first.
    static func remote(for repository: RemoteRepository, in remotes: [GitRemote]) -> GitRemote? {
        let preferred = ["upstream", "origin"]
        return remotes.compactMap { remote in remote.repository?.match(repository).map { (remote, $0) } }
            .min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                let left = preferred.firstIndex(of: lhs.0.name) ?? preferred.count
                let right = preferred.firstIndex(of: rhs.0.name) ?? preferred.count
                return left < right
            }?.0
    }

    /// The author's own fork, or one whose author lets maintainers push, when the viewer is one.
    static func canPushToFork(
        _ pullRequest: PullRequestDetails, head: RemoteRepository, viewer: String?, permission: RepositoryPermission?
    ) -> Bool {
        if let viewer, viewer.caseInsensitiveCompare(head.owner) == .orderedSame { return true }
        return pullRequest.maintainerCanModify && permission?.canMerge == true
    }

    /// The fork's owner, as `gh repo fork` names remotes, made unique among `taken`.
    static func newRemoteName(for repository: RemoteRepository, taken: Set<String>) -> String {
        let candidates = [repository.owner, "\(repository.owner)-\(repository.name)"]
        if let free = candidates.first(where: { !taken.contains($0) }) { return free }
        var number = 2
        while taken.contains("\(repository.owner)-\(number)") { number += 1 }
        return "\(repository.owner)-\(number)"
    }
}
