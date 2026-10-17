import Foundation

extension Repository {
    /// Untracked files beyond this many are counted but not listed; an unignored dependency
    /// folder can hold hundreds of thousands.
    static let untrackedLimit = 2000
    /// Untracked files are read to count their lines up to this size each.
    static let untrackedLineCountLimit = 4 * 1024 * 1024

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

        var totals = total.values.reduce(LineStats.zero, +)
        for index in changes.indices {
            switch changes[index].area {
            case .staged:
                changes[index].stats = staged[changes[index].path]
            case .unstaged:
                changes[index].stats = unstaged[changes[index].path]
            case .conflicted:
                changes[index].stats = unstaged[changes[index].path]
            case .untracked:
                let stats = untrackedStats(of: changes[index].path)
                changes[index].stats = stats
                totals = totals + (stats ?? .zero)
            }
        }
        changes.sort { lhs, rhs in
            lhs.area != rhs.area
                ? lhs.area < rhs.area : lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
        return RepositoryStatus(branch: branch, changes: changes, totals: totals, omittedUntrackedCount: omitted)
    }

    /// Line counts of a file git doesn't track, read directly rather than spawning git per file.
    private func untrackedStats(of path: String) -> LineStats? {
        let url = root.appending(path: path, directoryHint: .notDirectory)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true,
            let size = values.fileSize
        else { return nil }
        guard size <= Self.untrackedLineCountLimit, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }
        if FileVersions.isBinary(data) { return LineStats(isBinary: true) }
        var lines = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        if let last = data.last, last != 0x0A { lines += 1 }
        return LineStats(additions: lines)
    }

    /// The empty tree's id in this repository's hash algorithm.
    func emptyTree() async throws(GitError) -> String {
        let output = try await run(["hash-object", "-t", "tree", "/dev/null"], readOnly: true)
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
