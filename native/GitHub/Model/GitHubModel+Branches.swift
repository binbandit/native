import Exec
import Foundation
import GitHub

extension GitHubModel {
    // MARK: - Branches

    /// How long a branch's pull request is trusted. Each lookup is one `gh pr list --head` call, so
    /// results are cached and shared by every badge showing the same branch.
    static let branchMaxAge: TimeInterval = 120

    func pullRequest(for branch: BranchReference) -> PullRequestSummary? {
        branchPullRequests[branch]?.pullRequest
    }

    /// An explicit refresh (`maxAge: 0`) waits for older work, then bypasses the cache. A paired
    /// host's branch is asked of gh on that host, never of this Mac's.
    @discardableResult
    func loadPullRequest(for branch: BranchReference, maxAge: TimeInterval = branchMaxAge) async -> GitHubError? {
        if maxAge > 0, let cached = branchPullRequests[branch], Date.now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached.failure
        }
        var checkedAccounts = false
        while true {
            if let pending = branchLookupsInFlight[branch] {
                let failure = await pending.value
                if maxAge > 0 { return failure }
                if Task.isCancelled { return .cancelled }
                continue
            }
            // This Mac's gh only: a host's gh is installed and signed in there.
            if branch.host == nil, maxAge == 0, !checkedAccounts,
                availability == .notInstalled || availability == .notAuthenticated
            {
                // Wait for older lookups before recovery; they can still report an expired login.
                checkedAccounts = true
                await checkAccounts()
                continue
            }
            break
        }
        let reportsMissing = maxAge == 0
        let lookup: Task<GitHubError?, Never>
        if let host = branch.host {
            let source: RemoteBranchPullRequests.Source
            switch remoteBranches.source(for: host) {
            case .success(let found): source = found
            case .failure(let error): return recordBranchFailure(error, for: branch)
            }
            lookup = Task {
                let isCurrent: @MainActor () -> Bool = { self.remoteBranches.isCurrent(source, on: host) }
                let failure = await fetchPullRequest(
                    for: branch, using: source.cli, linkedPullRequest: source.linkedPullRequest,
                    reportsMissing: reportsMissing, isCurrent: isCurrent)
                if isCurrent() { branchLookupsInFlight[branch] = nil }
                return failure
            }
        } else {
            if availability == .notInstalled { return recordBranchFailure(.notInstalled, for: branch) }
            if availability == .notAuthenticated { return recordBranchFailure(.notAuthenticated(""), for: branch) }
            let revision = accountRevision
            lookup = Task {
                let cli = await cli(rereadEnvironment: availability == .notInstalled)
                let failure = await fetchPullRequest(
                    for: branch, using: cli, linkedPullRequest: linkedPullRequest, reportsMissing: reportsMissing,
                    isCurrent: { revision == self.accountRevision })
                if revision == accountRevision { branchLookupsInFlight[branch] = nil }
                return failure
            }
        }
        branchLookupsInFlight[branch] = lookup
        return await lookup.value
    }

    /// Asks `runner`'s gh (a paired host's) about `host`'s branches from now on, as for the host's
    /// next pairing. What an earlier pairing said or is still saying no longer counts.
    func answerBranches(
        on host: RemoteHostID, with runner: any CommandRunner,
        linkedPullRequest: @escaping @MainActor (BranchReference) async -> URL?
    ) {
        remoteBranches.install(runner, on: host, linkedPullRequest: linkedPullRequest)
        forgetBranches(on: host)
    }

    /// Forgets what one machine's gh said about its branches (`nil`: this Mac's) and drops what it's
    /// still looking up, once its answers no longer count.
    func forgetBranches(on host: RemoteHostID?) {
        for branch in branchPullRequests.keys where branch.host == host {
            branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .distantPast)
        }
        branchLookupsInFlight = branchLookupsInFlight.filter { $0.key.host != host }
    }

    /// `isCurrent` turns false once the answer no longer counts: another account here, another
    /// pairing with the host.
    private func fetchPullRequest(
        for branch: BranchReference, using cli: GitHubCLI,
        linkedPullRequest: (@MainActor (BranchReference) async -> URL?)?, reportsMissing: Bool,
        isCurrent: @MainActor () -> Bool
    ) async -> GitHubError? {
        do {
            let found: BranchPullRequests?
            if let link = await linkedPullRequest?(branch) {
                found = BranchPullRequests([try await cli.pullRequest(.url(link), in: .directory(branch.directory))])
            } else {
                found = try await cli.pullRequests(forBranch: branch.branch, in: .directory(branch.directory))
            }
            guard isCurrent() else { return .cancelled }
            branchPullRequests[branch] = BranchPullRequest(found, fetchedAt: .now)
            return nil
        } catch .notARepository {
            guard isCurrent() else { return .cancelled }
            branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .now)
            return nil
        } catch {
            guard isCurrent() else { return .cancelled }
            if case .notFound = error, !reportsMissing {
                branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .now)
                return nil
            }
            // A host's gh signing out says nothing about this Mac's account.
            if case .notAuthenticated = error, branch.host == nil { reportAuthenticationFailure() }
            return recordBranchFailure(error, for: branch)
        }
    }

    private func recordBranchFailure(_ error: GitHubError, for branch: BranchReference) -> GitHubError {
        var cached = branchPullRequests[branch] ?? BranchPullRequest(pullRequest: nil, fetchedAt: .now)
        cached.fetchedAt = .now
        cached.failure = error
        branchPullRequests[branch] = cached
        return error
    }

    /// What the last lookup found for a branch, with how fresh it is.
    func branchPullRequest(for branch: BranchReference) -> BranchPullRequest? {
        branchPullRequests[branch]
    }

    /// Reloads every badge showing this pull request, after a change made from Native (a merge, a
    /// close) so the sidebar says so at once rather than at the next refresh.
    func reloadBranches(showing url: URL) {
        for (branch, found) in branchPullRequests where found.pullRequest?.url == url {
            Task { await loadPullRequest(for: branch, maxAge: 0) }
        }
    }

    /// Forgets a branch's result so its badge reloads, e.g. after a push or a new pull request.
    func invalidate(_ branch: BranchReference) {
        branchPullRequests[branch] = nil
        Task { await loadPullRequest(for: branch) }
    }

    /// Reloads every badge whose result is older than `age`.
    func refreshBranches(olderThan age: TimeInterval) {
        let stale = branchPullRequests.filter { Date.now.timeIntervalSince($0.value.fetchedAt) >= age }.keys
        for branch in stale {
            Task { await loadPullRequest(for: branch, maxAge: age) }
        }
    }
}
