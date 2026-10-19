import ACP
import Foundation
import Git
import Observation

/// One Clean Up Merged for a project, from finding what's merged, through the review where the
/// user picks what goes, to the work and its undo. Nothing changes until `cleanUp()`.
@Observable
final class GitCleanupModel: Identifiable {
    enum Phase: Equatable {
        /// Looking, with what it's doing now.
        case scanning(String)
        /// The project isn't something there's anything to clean up in, and why.
        case unavailable(String)
        /// Looking failed; nothing was changed.
        case failed(details: String)
        case review
        case running
        /// Done; `states` says how each item went.
        case finished
    }

    enum ItemState: Equatable {
        case working
        case done
        case failed(String)
    }

    let id = UUID()
    let project: Project
    /// Set by the run too (GitCleanupModel+Run.swift).
    var phase: Phase = .scanning("Reading branches and worktrees…")
    private(set) var plan: MergedCleanupPlan?
    private(set) var items: [GitCleanupItem] = []
    /// What the user included. A branch whose worktree isn't included stays here but doesn't count.
    private(set) var checked: Set<GitCleanupItem.ID> = []
    /// How each included item went, once cleaning up has started.
    var states: [GitCleanupItem.ID: ItemState] = [:]
    /// What the last run did, for Undo.
    var undoRecord: GitCleanupUndo?
    @ObservationIgnored var isUndoOffered = false
    @ObservationIgnored weak var undoManager: UndoManager?

    @ObservationIgnored let services: GitCleanupServices
    /// Told when a run ends, so the center can close the sheet or bring it back.
    @ObservationIgnored var onFinished: (@MainActor (GitCleanupModel) -> Void)?
    @ObservationIgnored var work: Task<Void, Never>?

    init(project: Project, services: GitCleanupServices) {
        self.project = project
        self.services = services
    }

    // MARK: - Looking

    func scan() async {
        phase = .scanning("Reading branches and worktrees…")
        guard (try? await services.git.resolveGit().repository(at: project.url)) != nil else {
            phase = .unavailable(
                "“\(project.name)” isn't a git repository, so it has no branches or worktrees to clean up.")
            return
        }
        let prefix = await services.branchPrefix(project.url)
        let lookup = services.pullRequests
        let root = project.url
        do {
            let plan = try await services.git.mergedCleanupPlan(in: root, branchPrefix: prefix) { [weak self] queries in
                await self?.setScanning(
                    "Asking GitHub about \(queries.count == 1 ? "1 branch" : "\(queries.count) branches")…")
                let answer = await lookup(queries, root)
                await self?.setScanning("Measuring worktrees…")
                return answer
            }
            guard !Task.isCancelled else { return }
            self.plan = plan
            items = GitCleanupItem.items(from: plan, tasks: tasks(in:))
            checked = Set(items.filter(\.isCheckedByDefault).map(\.id))
            states = [:]
            phase = .review
        } catch {
            phase = .failed(details: error.localizedDescription)
        }
    }

    private func setScanning(_ step: String) {
        if case .scanning = phase { phase = .scanning(step) }
    }

    /// The project's tasks working in `folder` that aren't archived or being deleted.
    private func tasks(in folder: URL) -> [GitCleanupItem.TaskReference] {
        let app = services.app
        let prefix = GitCleanupItem.abbreviated(folder.resolvingSymlinksInPath())
        // Pinned tasks too: every task left working in a removed worktree would be stranded.
        let listed = app.allSessions(in: project.id).filter {
            !app.isArchived($0.id) && !app.pendingDeletionKeys.contains($0.id)
        }
        return listed.compactMap { summary in
            let cwd = GitCleanupItem.abbreviated(URL(filePath: summary.info.cwd).resolvingSymlinksInPath())
            guard cwd == prefix || cwd.hasPrefix(prefix + "/") else { return nil }
            return GitCleanupItem.TaskReference(
                key: summary.id, title: app.title(for: summary),
                isWorking: app.session(summary.id)?.phase == .prompting)
        }
    }

    // MARK: - Choosing

    func items(in group: GitCleanupItem.Group) -> [GitCleanupItem] {
        items.filter { $0.group == group }
    }

    /// The group's rows: all of them while choosing, then only what's being cleaned up.
    func shownItems(in group: GitCleanupItem.Group) -> [GitCleanupItem] {
        phase == .review ? items(in: group) : items(in: group).filter { states[$0.id] != nil || isIncluded($0) }
    }

    /// Whether the item can be included: a branch only with the worktree it's checked out in.
    func isEnabled(_ item: GitCleanupItem) -> Bool {
        guard phase == .review else { return false }
        return item.requires.map(checked.contains) ?? true
    }

    func isIncluded(_ item: GitCleanupItem) -> Bool {
        checked.contains(item.id) && (item.requires.map(checked.contains) ?? true)
    }

    func toggle(_ item: GitCleanupItem) {
        guard isEnabled(item) else { return }
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
    }

    func setGroup(_ group: GitCleanupItem.Group, included: Bool) {
        guard phase == .review else { return }
        for item in items(in: group) {
            if included { checked.insert(item.id) } else { checked.remove(item.id) }
        }
    }

    var included: [GitCleanupItem] {
        items.filter(isIncluded)
    }

    /// Bytes the included worktrees and folders take up.
    var reclaimedBytes: Int {
        included.compactMap(\.bytes).reduce(0, +)
    }

    /// "Archive 4 tasks and remove their worktrees", for what the group would do with what's
    /// included (or, with nothing included, what it could).
    func headline(of group: GitCleanupItem.Group) -> String {
        let all = items(in: group)
        let chosen = all.filter(isIncluded)
        let counted = chosen.isEmpty ? all : chosen
        let count = counted.count
        switch group {
        case .worktrees:
            let tasks = counted.reduce(0) { $0 + $1.tasks.count }
            if tasks == 0 { return count == 1 ? "Remove 1 worktree" : "Remove \(count) worktrees" }
            let archive = tasks == 1 ? "Archive 1 task" : "Archive \(tasks) tasks"
            if counted.allSatisfy({ $0.tasks.count == 1 }) { return "\(archive) and remove their worktrees" }
            return "\(archive) and remove \(count == 1 ? "1 worktree" : "\(count) worktrees")"
        case .branches: return count == 1 ? "Delete 1 local branch" : "Delete \(count) local branches"
        case .staleRecords:
            return count == 1 ? "Prune 1 stale worktree record" : "Prune \(count) stale worktree records"
        case .leftoverFolders:
            return count == 1 ? "Move 1 leftover folder to the Trash" : "Move \(count) leftover folders to the Trash"
        case .otherBranches:
            return count == 1 ? "Delete 1 other merged branch" : "Delete \(count) other merged branches"
        }
    }
}
