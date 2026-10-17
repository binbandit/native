import Foundation

/// A snapshot of the working tree: branch, changed files and their line counts.
public struct RepositoryStatus: Hashable, Sendable {
    public var branch: BranchStatus
    /// Every change, conflicted first, then staged, unstaged and untracked, each sorted by path.
    public var changes: [FileChange]
    /// Lines changed in the working tree against HEAD, untracked files included.
    public var totals: LineStats
    /// Untracked files left out of `changes` because there were too many.
    public var omittedUntrackedCount: Int

    public init(branch: BranchStatus, changes: [FileChange], totals: LineStats, omittedUntrackedCount: Int = 0) {
        self.branch = branch
        self.changes = changes
        self.totals = totals
        self.omittedUntrackedCount = omittedUntrackedCount
    }

    public func changes(in area: FileChange.Area) -> [FileChange] {
        changes.filter { $0.area == area }
    }

    public var staged: [FileChange] { changes(in: .staged) }
    public var unstaged: [FileChange] { changes(in: .unstaged) }
    public var untracked: [FileChange] { changes(in: .untracked) }
    public var conflicted: [FileChange] { changes(in: .conflicted) }

    public var isClean: Bool { changes.isEmpty && omittedUntrackedCount == 0 }

    /// Distinct files with any change, whichever areas they're in.
    public var changedFileCount: Int {
        Set(changes.map(\.path)).count + omittedUntrackedCount
    }
}
