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

    /// An explicit refresh (`maxAge: 0`) waits for older work, then bypasses the cache.
    @discardableResult
    func loadPullRequest(for branch: BranchReference, maxAge: TimeInterval = branchMaxAge) async -> GitHubError? {
        if maxAge > 0, let cached = branchPullRequests[branch], Date.now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached.failure
        }
        while let pending = branchLookupsInFlight[branch] {
            let failure = await pending.value
            if maxAge > 0 { return failure }
            if Task.isCancelled { return .cancelled }
        }
        if maxAge > 0 {
            if availability == .notInstalled { return .notInstalled }
            if availability == .notAuthenticated { return .notAuthenticated("") }
        }
        let revision = accountRevision
        let lookup = Task {
            let failure = await fetchPullRequest(for: branch, revision: revision, reportsMissing: maxAge == 0)
            if revision == accountRevision { branchLookupsInFlight[branch] = nil }
            return failure
        }
        branchLookupsInFlight[branch] = lookup
        return await lookup.value
    }

    private func fetchPullRequest(
        for branch: BranchReference, revision: Int, reportsMissing: Bool
    ) async -> GitHubError? {
        let cli = await cli(rereadEnvironment: availability == .notInstalled)
        do {
            let found: BranchPullRequests?
            if let link = await linkedPullRequest?(branch) {
                found = BranchPullRequests([try await cli.pullRequest(.url(link), in: .directory(branch.directory))])
            } else {
                found = try await cli.pullRequests(forBranch: branch.branch, in: .directory(branch.directory))
            }
            guard revision == accountRevision else { return .cancelled }
            branchPullRequests[branch] = BranchPullRequest(found, fetchedAt: .now)
            return nil
        } catch .notARepository {
            guard revision == accountRevision else { return .cancelled }
            branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .now)
            return nil
        } catch {
            guard revision == accountRevision else { return .cancelled }
            if case .notFound = error, !reportsMissing {
                branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .now)
                return nil
            }
            if case .notAuthenticated = error { reportAuthenticationFailure() }
            var cached = branchPullRequests[branch] ?? BranchPullRequest(pullRequest: nil, fetchedAt: .now)
            cached.fetchedAt = .now
            cached.failure = error
            branchPullRequests[branch] = cached
            return error
        }
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
