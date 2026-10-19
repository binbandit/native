import Foundation

extension Repository {
    /// Untracked files beyond this many are counted but not listed; an unignored dependency
    /// folder can hold hundreds of thousands.
    static let untrackedLimit = 2000

    /// The branch, every changed file with its line counts, and the working tree's totals.
    public func status() async throws(GitError) -> RepositoryStatus {
        try await lineStats(for: changedFiles())
    }

    /// The branch and every changed file, without line counts or totals: one `git status`, quick
    /// enough to list the files while `lineStats(for:)` diffs them.
    public func changedFiles() async throws(GitError) -> RepositoryStatus {
        let output = try await run(
            ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], readOnly: true)
        var (branch, changes) = try StatusParser.parse(output.text)

        let untrackedCount = changes.count { $0.area == .untracked }
        var omitted = 0
        if untrackedCount > Self.untrackedLimit {
            var kept = 0
            changes.removeAll { change in
                guard change.area == .untracked else { return false }
                kept += 1
                return kept > Self.untrackedLimit
            }
            omitted = untrackedCount - Self.untrackedLimit
        }
        changes.sort { lhs, rhs in
            lhs.area != rhs.area
                ? lhs.area < rhs.area : lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        return RepositoryStatus(branch: branch, changes: changes, totals: .zero, omittedUntrackedCount: omitted)
    }

    /// `status` with each change's line counts and the working tree's totals filled in.
    public func lineStats(for status: RepositoryStatus) async throws(GitError) -> RepositoryStatus {
        var status = status
        let numstat = ["--numstat", "-z", "--no-ext-diff", "--no-textconv", "--no-color"]
        // With nothing staged or conflicted the working tree differs from HEAD exactly as it does
        // from the index, so the unstaged diff gives the totals and git diffs each file once.
        let diffsAgainstHead = status.changes.contains { $0.area == .staged || $0.area == .conflicted }
        let staged: [String: LineStats]
        let unstaged: [String: LineStats]
        var total: [String: LineStats]?
        do {
            async let stagedOutput = run(["diff", "--cached", "-M"] + numstat, readOnly: true)
            async let unstagedOutput = run(["diff"] + numstat, readOnly: true)
            if diffsAgainstHead {
                // The working tree against HEAD, or against the empty tree before the first commit.
                let base = status.branch.isUnborn ? try await emptyTree() : "HEAD"
                total = NumstatParser.parse(try await run(["diff", "-M", base] + numstat, readOnly: true).text)
            }
            staged = NumstatParser.parse(try await stagedOutput.text)
            unstaged = NumstatParser.parse(try await unstagedOutput.text)
        } catch {
            throw error as? GitError ?? .unexpectedOutput("\(error)")
        }

        let untracked = try await untrackedStats(status.untracked.map(\.path))
        status.totals = (Array((total ?? unstaged).values) + Array(untracked.values)).reduce(LineStats.zero, +)
        for index in status.changes.indices {
            let path = status.changes[index].path
            switch status.changes[index].area {
            case .staged: status.changes[index].stats = staged[path]
            case .unstaged, .conflicted: status.changes[index].stats = unstaged[path]
            case .untracked: status.changes[index].stats = untracked[path]
            }
        }
        return status
    }

    /// Line counts of files git doesn't track, from one diff rather than reading each file.
    private func untrackedStats(_ paths: [String]) async throws(GitError) -> [String: LineStats] {
        guard !paths.isEmpty else { return [:] }
        let output = try await diffUntracked(
            paths, ["--numstat", "-z", "--no-ext-diff", "--no-textconv", "--no-color"])
        return NumstatParser.parse(output.text)
    }

    /// `git diff <arguments>` with the untracked `paths` marked intent-to-add in a scratch index,
    /// so they diff as new files while the real index stays untouched.
    func diffUntracked(_ paths: [String], _ arguments: [String]) async throws(GitError) -> Git.Output {
        try await withScratchIndex(copyingIndex: false) { scratch throws(GitError) in
            try await runWithPaths(["add", "--intent-to-add"], paths, environment: scratch)
            return try await run(["diff"] + arguments, readOnly: true, environment: scratch)
        }
    }

    /// The empty tree's id in this repository's hash algorithm.
    func emptyTree() async throws(GitError) -> String {
        let output = try await run(["hash-object", "-t", "tree", "/dev/null"], readOnly: true)
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
