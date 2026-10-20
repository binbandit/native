import Foundation
import Git
import Observation

/// A turn's or a branch's changes, committed or not, from their base to the working tree now, and
/// the selected file's diff. The inspector calls `refresh()` after each rescan of the repository;
/// a refresh that finds the same working tree (the same snapshot tree) does nothing more.
@Observable
final class GitRangeModel {
    enum State: Equatable {
        case loading
        case ready(GitRangeComparison)
        case failed(String)
    }

    /// A change and its diff; no content while it loads.
    struct ShownDiff: Equatable {
        let change: TreeChange
        let content: GitDiffContent?
        /// What the content was made from (`FileVersions.fingerprint`), to recheck it by.
        var fingerprint: Int?
    }

    private(set) var state = State.loading
    /// The path of the change whose diff is showing.
    var selection: String? {
        didSet {
            if selection != oldValue { loadSelectedDiff() }
        }
    }
    private(set) var shownDiff: ShownDiff?

    @ObservationIgnored private let baselines: GitTurnBaselines
    @ObservationIgnored private var repository: Repository?
    @ObservationIgnored private var request: GitRangeRequest?
    /// A file to select once it's in the comparison, by the path the card lists.
    @ObservationIgnored private var requestedFile: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var reloadsAfterLoad = false
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var diffLoadingTask: Task<Void, Never>?
    /// The change the user asked to see in full past the size diffs collapse at.
    @ObservationIgnored private var expandedPath: String?

    init(baselines: GitTurnBaselines = .shared) {
        self.baselines = baselines
    }

    /// A model frozen at `comparison`, for previews: it never runs git.
    init(fixed comparison: GitRangeComparison, diff: GitDiffContent? = nil) {
        baselines = .shared
        state = .ready(comparison)
        let first = comparison.edited.first ?? comparison.changes.first
        selection = first?.path
        shownDiff = first.map { ShownDiff(change: $0, content: diff) }
    }

    deinit {
        loadTask?.cancel()
        diffTask?.cancel()
        diffLoadingTask?.cancel()
    }

    var comparison: GitRangeComparison? {
        if case .ready(let comparison) = state { comparison } else { nil }
    }

    var selectedChange: TreeChange? {
        guard let selection else { return nil }
        return comparison?.changes.first { $0.path == selection }
    }

    /// Compares for `request`, and with `file` (a path as the card lists it), selects that file.
    func show(_ request: GitRangeRequest, in repository: Repository, selecting file: String? = nil) {
        if file != nil { requestedFile = file }
        guard request != self.request || repository != self.repository else {
            // Already showing it: just the file the card asked for, if it's in already.
            if let comparison { selectRequestedFile(in: comparison) }
            return
        }
        self.request = request
        self.repository = repository
        // A request only changes within one scope (the turn moved on, its edits grew), so what's on
        // screen stays until the new comparison replaces it.
        if comparison == nil { state = .loading }
        load()
    }

    /// Compares again, after the working tree may have changed.
    func refresh() {
        guard request != nil else { return }
        guard loadTask == nil else {
            reloadsAfterLoad = true
            return
        }
        load()
    }

    // MARK: - Comparing

    private func load() {
        loadTask?.cancel()
        reloadsAfterLoad = false
        guard let request, let repository else { return }
        loadTask = Task { [weak self] in
            await self?.compare(request, in: repository)
            guard !Task.isCancelled, let self else { return }
            self.loadTask = nil
            if self.reloadsAfterLoad { self.load() }
        }
    }

    private func compare(_ request: GitRangeRequest, in repository: Repository) async {
        do {
            let (base, baseID) = try await self.base(for: request, in: repository)
            let target = try await repository.snapshot().tree
            if let current = comparison, current.request == request, current.baseID == baseID,
                current.target == target, current.base == base
            {
                return
            }
            let changes = try await repository.treeChanges(from: baseID, to: target)
            guard !Task.isCancelled else { return }
            let edited: Set<String> =
                if case .turn(let turn) = request { turn.editedPaths(root: repository.root) } else { [] }
            apply(
                GitRangeComparison(
                    request: request, base: base, baseID: baseID, target: target, changes: changes,
                    editedPaths: edited))
        } catch {
            // A failed refresh keeps the last comparison on screen; a cancelled one isn't a failure.
            guard !Task.isCancelled, comparison == nil else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// Where `request` starts: a turn's recorded snapshot, else HEAD as it was when the turn began,
    /// else (no time either, as in replayed history) the branch's base.
    private func base(
        for request: GitRangeRequest, in repository: Repository
    ) async throws(GitError) -> (GitRangeBase, String?) {
        if case .turn(let turn) = request, let startedAt = turn.startedAt {
            if let baseline = baselines.baseline(of: turn.session, startedAt: startedAt),
                try await repository.hasObject(baseline.snapshot.tree)
            {
                return (.turnSnapshot, baseline.snapshot.tree)
            }
            return (.turnStartCommit(startedAt), try await repository.head(at: startedAt))
        }
        if let base = try await repository.branchBase() {
            return (.branch(base), base.commit)
        }
        return (.head, try await repository.headCommit())
    }

    private func apply(_ comparison: GitRangeComparison) {
        let previous = self.comparison
        let selected = selection
        state = .ready(comparison)
        selectRequestedFile(in: comparison)
        if let selection, comparison.changes.contains(where: { $0.path == selection }) {
            // The same file, perhaps changed again or compared from another base: its diff is
            // read again, and redrawn only if its sides changed.
            if selection == selected, previous?.target != comparison.target || previous?.baseID != comparison.baseID {
                loadSelectedDiff(unlessStill: shownDiff?.fingerprint)
            }
        } else {
            selection = (comparison.edited.first ?? comparison.changes.first)?.path
        }
    }

    private func selectRequestedFile(in comparison: GitRangeComparison) {
        guard let file = requestedFile, let repository else { return }
        requestedFile = nil
        let relative: String? =
            if case .turn(let turn) = comparison.request { turn.relativePath(of: file, root: repository.root) } else {
                file
            }
        if let relative, comparison.changes.contains(where: { $0.path == relative }) {
            selection = relative
        }
    }

    // MARK: - Diff

    /// Shows the selected change's diff in full, past the size diffs collapse at.
    func expandSelectedDiff() {
        guard let change = selectedChange else { return }
        expandedPath = change.path
        shownDiff = ShownDiff(change: change, content: nil)
        loadSelectedDiff()
    }

    /// Reads and diffs the selected change off the main thread; with `unchanged`, only if its
    /// sides no longer match it.
    private func loadSelectedDiff(unlessStill unchanged: Int? = nil) {
        diffTask?.cancel()
        diffLoadingTask?.cancel()
        guard let change = selectedChange, let comparison, let repository else {
            shownDiff = nil
            return
        }
        if shownDiff == nil {
            shownDiff = ShownDiff(change: change, content: nil)
        } else if shownDiff?.change.path != change.path {
            // Another file's diff stays up a moment, and gives way to a loader only if this one is slow.
            diffLoadingTask = Task { [weak self] in
                try? await Task.sleep(for: GitRepositoryModel.diffLoadingDelay)
                guard !Task.isCancelled, let self else { return }
                self.shownDiff = ShownDiff(change: change, content: nil)
            }
        }
        let expanded = expandedPath == change.path
        let (base, target) = (comparison.baseID, comparison.target)
        diffTask = Task { [weak self] in
            let loaded = await GitDiffContent.load(
                change, between: base, and: target, in: repository, expanded: expanded, unlessStill: unchanged)
            guard !Task.isCancelled, let self else { return }
            self.diffTask = nil
            guard self.selection == change.path else { return }
            guard let loaded else {
                // Unchanged sides: the same diff, under the change's new counts.
                if let shown = self.shownDiff {
                    self.shownDiff = ShownDiff(change: change, content: shown.content, fingerprint: shown.fingerprint)
                }
                return
            }
            self.diffLoadingTask?.cancel()
            self.shownDiff = ShownDiff(change: change, content: loaded.content, fingerprint: loaded.fingerprint)
        }
    }
}
