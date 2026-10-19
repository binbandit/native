import Foundation
import Git

/// One row of the Clean Up Merged sheet: something that will be archived, removed, deleted or
/// forgotten, why it qualifies, and what to watch out for before including it.
struct GitCleanupItem: Identifiable, Hashable {
    enum ID: Hashable {
        case worktree(URL)
        case branch(String)
        case staleRecord(URL)
        case leftoverFolder(URL)
    }

    /// The sheet's sections, in order.
    enum Group: Int, CaseIterable, Identifiable, Comparable {
        case worktrees, branches, staleRecords, leftoverFolders, otherBranches

        var id: Self { self }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// A task that works in a worktree, archived with it.
    struct TaskReference: Hashable {
        let key: SessionKey
        let title: String
        /// Its agent is in the middle of a turn.
        let isWorking: Bool
    }

    let id: ID
    let group: Group
    let title: String
    /// Why it qualifies: "Merged via PR #123", "Merged into main".
    let reason: String
    /// The merged pull request, for the reason's link.
    var pullRequest: URL?
    /// What it holds: the branch, or the commit a branch is at.
    var detail: String?
    /// Its folder, for the row's tooltip.
    var location: String?
    /// What to know before including it: "3 uncommitted files".
    var warning: String?
    var bytes: Int?
    var isCheckedByDefault = true
    /// The item this one can't happen without: a branch's worktree or stale record.
    var requires: ID?
    /// The tasks archived with a worktree.
    var tasks: [TaskReference] = []

    /// The sheet's rows for a plan. `tasks` finds the tasks working in a worktree folder.
    static func items(from plan: MergedCleanupPlan, tasks: (URL) -> [TaskReference]) -> [GitCleanupItem] {
        var items: [GitCleanupItem] = []
        let worktrees = Set(plan.worktrees.map(\.path))
        for worktree in plan.worktrees {
            let working = tasks(worktree.path)
            var item = GitCleanupItem(
                id: .worktree(worktree.path), group: .worktrees,
                title: Self.title(of: working, folder: worktree.path),
                reason: Self.describe(worktree.reason, base: plan.base, detached: worktree.branch == nil))
            item.pullRequest = worktree.reason.pullRequestURL
            item.detail = worktree.branch ?? "Detached HEAD"
            item.location = Self.abbreviated(worktree.path)
            item.bytes = worktree.bytes
            item.tasks = working
            var warnings: [String] = []
            switch worktree.uncommittedFiles {
            case nil: warnings.append("Couldn't check for uncommitted changes")
            case 0?: break
            case 1?: warnings.append("1 uncommitted file")
            case let count?: warnings.append("\(count) uncommitted files")
            }
            if working.contains(where: \.isWorking) {
                warnings.append(working.count == 1 ? "Its task is working" : "A task here is working")
            }
            item.warning = warnings.isEmpty ? nil : warnings.joined(separator: " · ")
            item.isCheckedByDefault = warnings.isEmpty
            items.append(item)
        }
        let staleRecords = Set(plan.staleRecords.map(\.path))
        for branch in plan.branches {
            var item = GitCleanupItem(
                id: .branch(branch.name), group: branch.isNative ? .branches : .otherBranches, title: branch.name,
                reason: Self.describe(branch.reason, base: plan.base))
            item.pullRequest = branch.reason.pullRequestURL
            item.detail = "At \(branch.tip.prefix(7))"
            item.isCheckedByDefault = branch.isNative
            if let folder = branch.checkedOutIn {
                if worktrees.contains(folder) {
                    item.requires = .worktree(folder)
                    item.detail = "At \(branch.tip.prefix(7)) · deleted after its worktree"
                } else if staleRecords.contains(folder) {
                    item.requires = .staleRecord(folder)
                }
            }
            items.append(item)
        }
        for record in plan.staleRecords {
            var item = GitCleanupItem(
                id: .staleRecord(record.path), group: .staleRecords, title: record.path.lastPathComponent,
                reason: "Its folder is gone")
            item.detail = record.branch
            item.location = Self.abbreviated(record.path)
            items.append(item)
        }
        #if os(macOS)
        // Moved to the Trash, which only this Mac's folders can be.
        for folder in plan.leftoverFolders {
            var item = GitCleanupItem(
                id: .leftoverFolder(folder.path), group: .leftoverFolders, title: folder.path.lastPathComponent,
                reason: "Left behind by a worktree git no longer knows")
            item.detail = Self.abbreviated(folder.path)
            item.location = item.detail
            item.bytes = folder.bytes
            items.append(item)
        }
        #endif
        return items.sorted { $0.group < $1.group }
    }

    // MARK: - Words

    static func describe(_ reason: MergedCleanupPlan.Reason, base: String, detached: Bool = false) -> String {
        switch reason {
        case .pullRequest(let number, _, let into) where into == base: "Merged via PR #\(number)"
        case .pullRequest(let number, _, let into): "Merged into \(into) via PR #\(number)"
        case .ancestry(let base): detached ? "Its commit is in \(base)" : "Merged into \(base)"
        case .sameContent(let base): "Its changes are already in \(base) (squash or rebase merge)"
        }
    }

    static func describe(_ why: MergedCleanupPlan.Kept.Why, base: String) -> String {
        switch why {
        case .unmergedCommits(1): "1 commit isn't in \(base)"
        case .unmergedCommits(let count): "\(count) commits aren't in \(base)"
        case .changedSincePullRequest(let number): "Has commits that aren't in PR #\(number)"
        case .noCommits: "No commits yet"
        case .protected: "Protected branch"
        case .checkedOutElsewhere(let folder): "Checked out in \(abbreviated(folder)), which isn't Native's"
        case .locked: "Its worktree is locked"
        }
    }

    /// "Fix login bug", "Fix login bug and 1 more", or the folder's name when no task works there.
    private static func title(of tasks: [TaskReference], folder: URL) -> String {
        guard let first = tasks.first else { return folder.lastPathComponent }
        return tasks.count == 1 ? first.title : "\(first.title) and \(tasks.count - 1) more"
    }

    /// The path with the home folder as `~`.
    static func abbreviated(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = NSHomeDirectory()
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        return trimmed.hasPrefix(home + "/") ? "~" + trimmed.dropFirst(home.count) : trimmed
    }
}

extension MergedCleanupPlan.Reason {
    fileprivate var pullRequestURL: URL? {
        if case .pullRequest(_, let url, _) = self { url } else { nil }
    }
}
