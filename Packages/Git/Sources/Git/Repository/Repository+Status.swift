import Foundation

extension Repository {
    /// Untracked files beyond this many are counted but not listed; an unignored dependency
    /// folder can hold hundreds of thousands.
    static let untrackedLimit = 2000

    /// The branch, every changed file with its line counts, and the working tree's totals.
    public func status() async throws(GitError) -> RepositoryStatus {
        let output = try await run(
            ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], readOnly: true)
        var (branch, changes) = try StatusParser.parse(output.text)

        // The working tree against HEAD, or against the empty tree before the first commit.
        let base = branch.isUnborn ? try await emptyTree() : "HEAD"
        let numstat = ["--numstat", "-z", "--no-ext-diff", "--no-textconv", "--no-color"]
        let staged: [String: LineStats]
        let unstaged: [String: LineStats]
        let total: [String: LineStats]
        do {
            async let stagedOutput = run(["diff", "--cached", "-M"] + numstat, readOnly: true)
            async let unstagedOutput = run(["diff"] + numstat, readOnly: true)
            async let totalOutput = run(["diff", "-M", base] + numstat, readOnly: true)
            staged = NumstatParser.parse(try await stagedOutput.text)
            unstaged = NumstatParser.parse(try await unstagedOutput.text)
            total = NumstatParser.parse(try await totalOutput.text)
        } catch {
            throw error as? GitError ?? .unexpectedOutput("\(error)")
        }

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

        let untracked = try await untrackedStats(changes.filter { $0.area == .untracked }.map(\.path))
        let totals = (Array(total.values) + Array(untracked.values)).reduce(LineStats.zero, +)
        for index in changes.indices {
            switch changes[index].area {
            case .staged:
                changes[index].stats = staged[changes[index].path]
            case .unstaged:
                changes[index].stats = unstaged[changes[index].path]
            case .conflicted:
                changes[index].stats = unstaged[changes[index].path]
            case .untracked:
                changes[index].stats = untracked[changes[index].path]
            }
        }
        changes.sort { lhs, rhs in
            lhs.area != rhs.area
                ? lhs.area < rhs.area : lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        return RepositoryStatus(branch: branch, changes: changes, totals: totals, omittedUntrackedCount: omitted)
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
