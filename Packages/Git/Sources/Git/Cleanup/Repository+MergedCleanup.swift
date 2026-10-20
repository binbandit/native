import Foundation

/// "Clean Up Merged": which of Native's worktrees and which local branches hold work that's already
/// in the base branch. Nothing is ever offered when it could lose work: the base, the main
/// checkout's branch and protected names stay, and so does any branch with commits the base (or
/// the pull request that merged it) doesn't have.
extension Repository {
    /// What a branch is, as far as cleaning up goes.
    enum Verdict {
        case merged(MergedCleanupPlan.Reason)
        case kept(MergedCleanupPlan.Kept.Why)
    }

    /// Finds what cleaning up merged work would do, changing nothing. A branch is merged when its
    /// tip is in the base branch's history (`git branch --merged`), when GitHub says a pull request
    /// with its commits was merged (`pullRequests` is asked once, about the branches that were
    /// pushed), or, when GitHub can't say, when merging it into the base would change nothing.
    public func mergedCleanupPlan(
        _ options: MergedCleanupOptions,
        pullRequests: @Sendable ([CleanupPullRequestLookup.Query]) async -> CleanupPullRequestLookup
    ) async throws(GitError) -> MergedCleanupPlan {
        let base = try await cleanupBase(preferred: options.base)
        let worktrees = try await worktrees()
        let location = await physicalPath(of: options.taskLocation) ?? Self.cleanupSpelling(of: options.taskLocation)
        func isTaskWorktree(_ worktree: Worktree) -> Bool {
            !worktree.isMain && Self.cleanupSpelling(of: worktree.path).hasPrefix(location + "/")
        }
        let mainBranch = worktrees.first(where: \.isMain)?.branch
        var checkouts: [String: Worktree] = [:]
        for worktree in worktrees where !worktree.isMain {
            if let branch = worktree.branch { checkouts[branch] = worktree }
        }

        let branches = try await localBranchFacts()
        let remoteNames = try await remoteBranchNames()
        let merged = try await branchesMerged(into: base)
        let marked = try await notes("nativeProvisional").merging(try await notes("nativeCreated")) {
            $0 == "true" ? $0 : $1
        }
        let links = try await notes("nativePullRequest")
        func isNative(_ branch: String) -> Bool {
            (!options.branchPrefix.isEmpty && branch.hasPrefix(options.branchPrefix)) || marked[branch] == "true"
                || links[branch] != nil || checkouts[branch].map(isTaskWorktree) == true
        }

        var plan = MergedCleanupPlan(base: base.name)
        var candidates: [LocalBranchFacts] = []
        for branch in branches {
            let checkout = checkouts[branch.name].flatMap { $0.isPrunable ? nil : $0 }
            let why: MergedCleanupPlan.Kept.Why?
            if branch.name == base.name || branch.name == mainBranch || options.isProtected(branch.name) {
                why = .protected
            } else if let checkout, !isTaskWorktree(checkout) {
                why = .checkedOutElsewhere(checkout.path)
            } else if let checkout, checkout.isLocked {
                why = .locked
            } else {
                candidates.append(branch)
                continue
            }
            if let why, isNative(branch.name) {
                plan.kept.append(.init(branch: branch.name, worktree: checkout?.path, why: why))
            }
        }

        func isPublished(_ branch: LocalBranchFacts) -> Bool {
            branch.upstreamRef != nil || remoteNames.contains(branch.name)
        }
        let queries = candidates.filter { isPublished($0) || links[$0.name] != nil }.map { branch in
            CleanupPullRequestLookup.Query(
                branch: branch.name,
                head: branch.upstreamRef.map { String($0.dropFirst("refs/heads/".count)) } ?? branch.name,
                linkedPullRequest: links[branch.name].flatMap(URL.init(string:)))
        }
        var mergedPullRequests: [String: [CleanupPullRequestLookup.PullRequest]] = [:]
        if !queries.isEmpty {
            switch await pullRequests(queries) {
            case .found(let found):
                mergedPullRequests = found
                plan.pullRequestCheck = .checked
            case .unavailable(let reason):
                plan.pullRequestCheck = .unavailable(reason)
            }
        }

        for branch in candidates {
            let verdict = try await verdict(
                for: branch, base: base, isMerged: merged.contains(branch.name), isPublished: isPublished(branch),
                pullRequests: mergedPullRequests[branch.name] ?? [],
                comparesContent: !isPublished(branch) || plan.pullRequestCheck != .checked)
            let checkout = checkouts[branch.name]
            switch verdict {
            case .merged(let reason):
                plan.branches.append(
                    .init(
                        name: branch.name, tip: branch.tip, reason: reason, isNative: isNative(branch.name),
                        checkedOutIn: checkout?.path))
                if let checkout, !checkout.isPrunable {
                    plan.worktrees.append(
                        .init(path: checkout.path, branch: branch.name, reason: reason, uncommittedFiles: nil))
                }
            case .kept(let why) where isNative(branch.name):
                plan.kept.append(.init(branch: branch.name, worktree: checkout?.path, why: why))
            case .kept:
                break
            }
        }

        // Detached task worktrees have no branch to judge; their commit is.
        for worktree in worktrees where isTaskWorktree(worktree) && worktree.isDetached && !worktree.isPrunable {
            guard let head = worktree.head else { continue }
            if worktree.isLocked {
                plan.kept.append(.init(branch: nil, worktree: worktree.path, why: .locked))
            } else if try await isIn(base, commit: head) {
                plan.worktrees.append(
                    .init(path: worktree.path, branch: nil, reason: .ancestry(base: base.name), uncommittedFiles: nil))
            } else {
                let count = try await commitsNotIn(base, revision: head)
                plan.kept.append(.init(branch: nil, worktree: worktree.path, why: .unmergedCommits(count)))
            }
        }

        plan.staleRecords = worktrees.filter { $0.isPrunable && !$0.isLocked }.map {
            .init(path: $0.path, branch: $0.branch)
        }
        let listed = Set(worktrees.map { Self.cleanupSpelling(of: $0.path) })
        plan.leftoverFolders = await leftoverTaskFolders(in: location, listed: listed).map {
            .init(path: $0, bytes: nil)
        }
        await measure(&plan)
        plan.worktrees.sort { $0.path.lastPathComponent < $1.path.lastPathComponent }
        plan.branches.sort { $0.name < $1.name }
        return plan
    }

    func verdict(
        for branch: LocalBranchFacts, base: CleanupBase, isMerged: Bool, isPublished: Bool,
        pullRequests: [CleanupPullRequestLookup.PullRequest], comparesContent: Bool
    ) async throws(GitError) -> Verdict {
        // The local branch at, or behind, a merged pull request's head has nothing the pull request
        // didn't, however it was merged.
        for pullRequest in pullRequests where pullRequest.headCommit == branch.tip {
            return .merged(.pullRequest(number: pullRequest.number, url: pullRequest.url, base: pullRequest.base))
        }
        for pullRequest in pullRequests {
            guard try await hasCommit(pullRequest.headCommit),
                try await contains(branch.tip, in: pullRequest.headCommit)
            else { continue }
            return .merged(.pullRequest(number: pullRequest.number, url: pullRequest.url, base: pullRequest.base))
        }
        if isMerged {
            // A pushed branch's commits were on the remote too, so it had work of its own.
            let hasWork = isPublished ? true : await hasCommitsOfItsOwn(branch.name)
            return hasWork ? .merged(.ancestry(base: base.name)) : .kept(.noCommits)
        }
        if comparesContent, await changesAreIn(base, branch: branch.name) {
            return .merged(.sameContent(base: base.name))
        }
        if let pullRequest = pullRequests.first {
            return .kept(.changedSincePullRequest(number: pullRequest.number))
        }
        return .kept(.unmergedCommits(try await commitsNotIn(base, revision: "refs/heads/\(branch.name)")))
    }

    /// Fills in the worktrees' uncommitted file counts and the folders' sizes, all at once.
    private func measure(_ plan: inout MergedCleanupPlan) async {
        enum Measurement {
            case worktree(Int, uncommitted: Int?, bytes: Int?)
            case folder(Int, bytes: Int?)
        }
        let results = await withTaskGroup(of: Measurement.self) { group in
            for (index, worktree) in plan.worktrees.enumerated() {
                group.addTask {
                    async let uncommitted = try? self.uncommittedFileCount(in: worktree.path)
                    async let bytes = self.diskUsage(of: worktree.path)
                    return .worktree(index, uncommitted: await uncommitted, bytes: await bytes)
                }
            }
            for (index, folder) in plan.leftoverFolders.enumerated() {
                group.addTask { .folder(index, bytes: await self.diskUsage(of: folder.path)) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        for result in results {
            switch result {
            case .worktree(let index, let uncommitted, let bytes):
                plan.worktrees[index].uncommittedFiles = uncommitted
                plan.worktrees[index].bytes = bytes
            case .folder(let index, let bytes):
                plan.leftoverFolders[index].bytes = bytes
            }
        }
    }

    /// A folder's path without a trailing slash. Not standardized: that turns git's
    /// `/private/var/…` into `/var/…`, and the paths compared here are all physical ones.
    static func cleanupSpelling(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
