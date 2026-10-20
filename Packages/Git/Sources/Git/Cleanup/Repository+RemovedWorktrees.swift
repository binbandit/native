import Foundation

/// Tasks whose worktree folders were removed by something other than Native's archive. Each is tied
/// to the branch it was on, and that branch is judged the way Clean Up Merged judges branches
/// (`mergedCleanupPlan`), so a task is done exactly when cleaning up would have taken its branch.
extension Repository {
    /// What each of `tasks` should become: done when its branch's work is in the base (or it never
    /// had commits of its own) or its branch is gone; in sight when its branch has work the base
    /// doesn't, or Native can't tell which branch it was. The branch is git's own record when the
    /// folder was deleted without a prune, else what `branchEvidence` ties to the folder. Changes
    /// nothing. `pullRequests` is asked once, about the pushed branches.
    public func removedWorktreeVerdicts(
        for tasks: [RemovedWorktreeTask], options: MergedCleanupOptions,
        pullRequests: @Sendable ([CleanupPullRequestLookup.Query]) async -> CleanupPullRequestLookup
    ) async throws(GitError) -> [RemovedWorktreeVerdict] {
        guard !tasks.isEmpty else { return [] }
        let base = try await cleanupBase(preferred: options.base)
        var recorded: [String: String] = [:]
        for worktree in try await worktrees() where worktree.isPrunable {
            if let branch = worktree.branch { recorded[Self.cleanupSpelling(of: worktree.path)] = branch }
        }
        let candidates = try await removedBranchCandidates()
        let facts = Dictionary(try await localBranchFacts().map { ($0.name, $0) }) { first, _ in first }

        var ties: [Tie] = []
        for task in tasks {
            if let branch = recorded[Self.cleanupSpelling(of: task.path)] {
                ties.append(facts[branch] == nil ? .gone : .branch(branch))
                continue
            }
            let tiers = try await branchEvidence(
                folderName: task.path.lastPathComponent, title: task.title, among: candidates)
            guard let matches = tiers.first(where: { !$0.isEmpty }) else {
                ties.append(.gone)
                continue
            }
            if matches.count > 1 {
                ties.append(.ambiguous(matches.map(\.name).sorted()))
            } else if let match = matches.first, !match.isArchivedCopy {
                ties.append(.branch(match.name))
            } else {
                ties.append(.gone)
            }
        }

        let verdicts = try await verdicts(
            for: Set(ties.compactMap(\.branch)).compactMap { facts[$0] }, base: base, pullRequests: pullRequests)
        return ties.map { tie in
            switch tie {
            case .branch(let name):
                switch verdicts[name] {
                case .merged(let reason)?: .done(.merged(branch: name, reason))
                case .kept(.noCommits)?: .done(.noCommits(branch: name))
                case .kept(let why)?: .unmerged(branch: name, why: why)
                case nil: .done(.branchGone)
                }
            case .gone: .done(.branchGone)
            case .ambiguous(let names): .unknownBranch(names)
            }
        }
    }

    /// Each branch judged once, asking about merged pull requests for the pushed ones, as the plan does.
    private func verdicts(
        for branches: [LocalBranchFacts], base: CleanupBase,
        pullRequests: @Sendable ([CleanupPullRequestLookup.Query]) async -> CleanupPullRequestLookup
    ) async throws(GitError) -> [String: Verdict] {
        guard !branches.isEmpty else { return [:] }
        let remoteNames = try await remoteBranchNames()
        let merged = try await branchesMerged(into: base)
        let links = try await notes("nativePullRequest")
        func isPublished(_ branch: LocalBranchFacts) -> Bool {
            branch.upstreamRef != nil || remoteNames.contains(branch.name)
        }
        let queries = branches.filter { isPublished($0) || links[$0.name] != nil }.map { branch in
            CleanupPullRequestLookup.Query(
                branch: branch.name,
                head: branch.upstreamRef.map { String($0.dropFirst("refs/heads/".count)) } ?? branch.name,
                linkedPullRequest: links[branch.name].flatMap(URL.init(string:)))
        }
        var found: [String: [CleanupPullRequestLookup.PullRequest]] = [:]
        var checked = false
        if !queries.isEmpty, case .found(let pullRequests) = await pullRequests(queries) {
            found = pullRequests
            checked = true
        }
        var verdicts: [String: Verdict] = [:]
        for branch in branches {
            verdicts[branch.name] = try await verdict(
                for: branch, base: base, isMerged: merged.contains(branch.name), isPublished: isPublished(branch),
                pullRequests: found[branch.name] ?? [], comparesContent: !isPublished(branch) || !checked)
        }
        return verdicts
    }
}

/// The branch a removed task worktree was on, as far as the repository can tell.
private enum Tie {
    case branch(String)
    /// Deleted, or kept only as Native's copy of a deleted one.
    case gone
    case ambiguous([String])

    var branch: String? {
        if case .branch(let name) = self { name } else { nil }
    }
}
