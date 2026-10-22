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

    /// Loads the branch's pull request unless a result younger than `maxAge` is cached.
    func loadPullRequest(for branch: BranchReference, maxAge: TimeInterval = branchMaxAge) async {
        if let cached = branchPullRequests[branch], Date.now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return
        }
        guard !branchLookupsInFlight.contains(branch) else { return }
        // Without gh or a login there's nothing to show, and the list explains why.
        if availability == .notInstalled || availability == .notAuthenticated { return }

        let revision = accountRevision
        branchLookupsInFlight.insert(branch)
        defer { if revision == accountRevision { branchLookupsInFlight.remove(branch) } }
        let cli = await cli()
        do {
            let found: BranchPullRequests?
            if let link = await linkedPullRequest?(branch) {
                found = BranchPullRequests([try await cli.pullRequest(.url(link), in: .directory(branch.directory))])
            } else {
                found = try await cli.pullRequests(forBranch: branch.branch, in: .directory(branch.directory))
            }
            guard revision == accountRevision else { return }
            branchPullRequests[branch] = BranchPullRequest(found, fetchedAt: .now)
        } catch .notARepository, .notFound {
            guard revision == accountRevision else { return }
            branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .now)
        } catch {
            guard revision == accountRevision else { return }
            // A lost login anywhere means gh is signed out, which the list and every card then say.
            if case .notAuthenticated = error { reportAuthenticationFailure() }
            // Keep showing what was there, saying why it may be old; the next refresh tries again.
            if var cached = branchPullRequests[branch] {
                cached.fetchedAt = .now
                cached.failure = error
                branchPullRequests[branch] = cached
            }
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
