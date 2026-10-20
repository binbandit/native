import Foundation
import Git
import Observation

/// Live git state for one working folder: branch, changes and the selected file's diff, kept fresh
/// by the repository's change monitor. Every git action the UI offers goes through this model.
@Observable
final class GitRepositoryModel {
    enum State: Equatable {
        case loading
        case notRepository
        case ready
        case failed(String)
    }

    let folder: URL
    private(set) var state = State.loading
    private(set) var repository: Repository?
    private(set) var status: RepositoryStatus? {
        didSet { mirrorStatus() }
    }
    /// "main ↑2 ↓1 · 5 changed" for a window subtitle; `nil` outside a repository. This and
    /// `canCommit` mirror `status`, so views that show only these don't update with every rescan.
    private(set) var summary: String?
    /// There are changes to commit and no conflicts in the way.
    private(set) var canCommit = false
    /// Whether there's anywhere to push; publishing is only offered when there is.
    private(set) var hasRemote = false
    /// The change whose diff is showing.
    var selection: FileChange.ID? {
        didSet {
            if selection != oldValue { loadSelectedDiff() }
        }
    }
    /// The diff on screen. It moves to a newly selected file once that file's diff is ready, so a
    /// quick load replaces the previous diff in one draw; a slow one shows as loading after
    /// `diffLoadingDelay`.
    private(set) var shownDiff: ShownDiff?
    /// A stage, commit or push is running.
    private(set) var isWorking = false
    /// Feedback for the last action: a failure with its next step, or a confirmation.
    private(set) var notice: GitNotice?
    /// The commit form's message, kept while the form is closed so a draft isn't lost.
    var commitMessage = ""
    /// Goes up after every rescan, whether or not the status changed: an edit can keep its line
    /// counts, so what's compared beyond the status (a turn's changes) checks again on it.
    private(set) var scanCount = 0

    @ObservationIgnored let resolveGit: () async -> Git?
    /// Called after each successful push with the checkout it ran in and the branch.
    @ObservationIgnored var onPushed: ((_ project: URL, _ branch: String) -> Void)?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: PendingRefresh?
    @ObservationIgnored private var isScanning = false
    @ObservationIgnored private var lastScan: ContinuousClock.Instant?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var diffLoadingTask: Task<Void, Never>?
    /// The change the user asked to see in full past the size diffs collapse at.
    @ObservationIgnored private var expandedDiffID: FileChange.ID?

    /// A change and its diff; no content while it loads.
    struct ShownDiff: Equatable {
        let change: FileChange
        let content: GitDiffContent?
        /// What the content was made from (`FileVersions.fingerprint`), to recheck it by.
        var fingerprint: Int?
    }

    /// A rescan someone asked for: right away (an action, the user), or once file events settle.
    private enum PendingRefresh {
        case now
        case settled
    }

    /// How long file events settle before a rescan, so a burst of agent writes costs one scan.
    static let settleDelay = Duration.milliseconds(250)
    /// While file events keep coming (an agent writing), rescans run at most this often.
    static let busyInterval = Duration.seconds(1)
    /// Beyond this many changed paths an event batch isn't worth checking against `.gitignore`.
    static let ignoreCheckLimit = 500
    /// How long a diff may take before the pane shows it loading.
    static let diffLoadingDelay = Duration.milliseconds(150)
    /// How long a plain confirmation stays up.
    static let confirmationDuration = Duration.seconds(4)

    init(folder: URL, git: @escaping () async -> Git?) {
        self.folder = folder
        resolveGit = git
        refresh()
    }

    /// A model frozen at `status`, for previews and fixtures: it never runs git.
    init(folder: URL, fixedStatus: RepositoryStatus, diff: GitDiffContent? = nil) {
        self.folder = folder
        resolveGit = { nil }
        status = fixedStatus
        state = .ready
        selection = fixedStatus.changes.first?.id
        shownDiff = fixedStatus.changes.first.map { ShownDiff(change: $0, content: diff) }
        mirrorStatus()
    }

    deinit {
        refreshTask?.cancel()
        watchTask?.cancel()
        diffTask?.cancel()
        diffLoadingTask?.cancel()
    }

    // MARK: - Derived

    var branch: BranchStatus? { status?.branch }
    var changes: [FileChange] { status?.changes ?? [] }
    var totals: LineStats { status?.totals ?? .zero }
    var isDirty: Bool { status.map { !$0.isClean } ?? false }

    /// There are commits to push, or a branch to publish, and somewhere to push them.
    var canPush: Bool {
        guard let branch, hasRemote, !branch.isDetached, !branch.isUnborn else { return false }
        return branch.ahead > 0 || branch.upstream == nil
    }

    var selectedChange: FileChange? {
        guard let selection else { return nil }
        return changes.first { $0.id == selection }
    }

    /// Writes only what changed, since writing notifies observers even with an equal value.
    private func mirrorStatus() {
        let summary = Self.summary(of: status)
        if self.summary != summary { self.summary = summary }
        let canCommit = status.map { !$0.isClean && $0.conflicted.isEmpty } ?? false
        if self.canCommit != canCommit { self.canCommit = canCommit }
    }

    private static func summary(of status: RepositoryStatus?) -> String? {
        guard let status else { return nil }
        let branch = status.branch
        var parts = [branch.displayName]
        if branch.ahead > 0 { parts[0] += " ↑\(branch.ahead)" }
        if branch.behind > 0 { parts[0] += " ↓\(branch.behind)" }
        if !status.isClean { parts.append("\(status.changedFileCount) changed") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Refreshing

    /// Rescans soon. Calls while a scan runs coalesce into one more scan after it.
    func refresh() {
        requestRefresh(.now)
    }

    /// Rescans once things settle, for signals that come in bursts, like an agent's file edits;
    /// coalesces with the repository's own file events.
    func refreshWhenSettled() {
        requestRefresh(.settled)
    }

    /// Rescans and waits for the result.
    func refreshNow() async {
        refresh()
        await refreshTask?.value
    }

    private func requestRefresh(_ request: PendingRefresh) {
        pendingRefresh = request == .now ? .now : pendingRefresh ?? .settled
        if let refreshTask {
            // A rescan still waiting for file events to settle runs now when asked for directly.
            guard request == .now, !isScanning else { return }
            refreshTask.cancel()
        }
        refreshTask = Task { [weak self] in await self?.runPendingRefreshes() }
    }

    /// Runs until nothing is pending. A direct refresh that takes over cancels this task, possibly
    /// before it has started, and the pending request is then the new task's to run.
    private func runPendingRefreshes() async {
        while let pending = pendingRefresh {
            if pending == .settled {
                do { try await Task.sleep(for: settledRefreshDelay) } catch { return }
            }
            if Task.isCancelled { return }
            pendingRefresh = nil
            isScanning = true
            await load()
            isScanning = false
            lastScan = .now
            scanCount += 1
        }
        refreshTask = nil
    }

    /// The settle delay, stretched so that file events arriving all the time cost one scan per
    /// `busyInterval`.
    private var settledRefreshDelay: Duration {
        guard let lastScan else { return Self.settleDelay }
        return max(Self.settleDelay, Self.busyInterval - lastScan.duration(to: .now))
    }

    private func load() async {
        do {
            guard let repository = try await currentRepository() else {
                state = .notRepository
                status = nil
                return
            }
            async let remotes = repository.remotes()
            let files = try await repository.changedFiles()
            hasRemote = !(try await remotes).isEmpty
            guard !Task.isCancelled else { return }
            // The first scan lists the files while git counts their lines; later scans keep the
            // last counts on screen until the new ones are in.
            if status == nil {
                apply(files)
                state = .ready
            }
            let status = try await repository.lineStats(for: files)
            guard !Task.isCancelled else { return }
            apply(status)
            state = .ready
            recheckShownDiff()
        } catch {
            // A failed rescan keeps the last good status on screen; a cancelled one isn't a failure.
            if status == nil, !Task.isCancelled { state = .failed(error.localizedDescription) }
        }
    }

    private func currentRepository() async throws -> Repository? {
        if let repository { return repository }
        guard let git = await resolveGit(), let repository = try await git.repository(at: folder) else {
            return nil
        }
        self.repository = repository
        startWatching(repository)
        return repository
    }

    private func apply(_ newStatus: RepositoryStatus) {
        let previous = status
        guard newStatus != previous else { return }
        status = newStatus
        // Keep the same file selected when it moves between areas, e.g. after staging it.
        if let selected = previous?.changes.first(where: { $0.id == selection }),
            !newStatus.changes.contains(where: { $0.id == selection })
        {
            selection = newStatus.changes.first { $0.path == selected.path }?.id ?? newStatus.changes.first?.id
        } else if selection == nil || !newStatus.changes.contains(where: { $0.id == selection }) {
            selection = newStatus.changes.first?.id
        }
        // The selected file itself may have changed on disk.
        if let selected = selectedChange,
            previous?.changes.first(where: { $0.id == selected.id }) != selected || shownDiff == nil
        {
            loadSelectedDiff()
        }
    }

    // MARK: - Actions

    /// Runs one action at a time, then rescans. The action's notice, or `nil`, replaces the last
    /// one; a failure becomes a notice with its reason and next step.
    func perform(_ operation: GitNotice.Operation, _ action: (Repository) async throws -> GitNotice?) async {
        do {
            try await performThrowing(action)
        } catch {
            show(GitNotice(failure: error, during: operation))
        }
    }

    /// `perform`, leaving failures to the caller: the commit form shows them itself.
    func performThrowing(_ action: (Repository) async throws -> GitNotice?) async throws {
        guard let repository, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            show(try await action(repository))
        } catch {
            await refreshNow()
            throw error
        }
        await refreshNow()
    }

    func show(_ notice: GitNotice?) {
        self.notice = notice
        // Plain confirmations fade; ones that offer a way back stay until dismissed or replaced.
        guard let notice, notice.tone == .success, notice.action == nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.confirmationDuration)
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: - Watching

    private func startWatching(_ repository: Repository) {
        guard watchTask == nil else { return }
        let changes = repository.changes()
        watchTask = Task { [weak self] in
            for await change in changes {
                guard let self else { return }
                // A rescan that hasn't started yet covers these events too.
                guard self.pendingRefresh == nil else { continue }
                if await self.matters(change, in: repository) {
                    self.requestRefresh(.settled)
                }
            }
        }
    }

    /// Whether a batch of file events can change the status: writes to ignored files (build
    /// output, `node_modules`) can't, and agents cause plenty of those.
    private func matters(_ change: RepositoryChange, in repository: Repository) async -> Bool {
        if change.gitStateChanged || change.paths.count > Self.ignoreCheckLimit { return true }
        guard let ignored = try? await repository.ignoredPaths(among: Array(change.paths)) else { return true }
        return ignored.count < change.paths.count
    }

    // MARK: - Diff

    /// Shows the selected change's diff in full, past the size diffs collapse at.
    func expandSelectedDiff() {
        guard let change = selectedChange else { return }
        expandedDiffID = change.id
        shownDiff = ShownDiff(change: change, content: nil)
        loadSelectedDiff()
    }

    /// After a scan: reloads the diff on screen if its file changed. The status can't always tell,
    /// since an edit can keep its line counts, so this compares the file's contents, which costs
    /// reading the one file however many changed.
    private func recheckShownDiff() {
        guard diffTask == nil, let shown = shownDiff, let fingerprint = shown.fingerprint,
            shown.change == selectedChange
        else { return }
        loadSelectedDiff(unlessStill: fingerprint)
    }

    /// Reads and diffs the selected change off the main thread; with `unchanged`, only if its
    /// contents no longer match it.
    private func loadSelectedDiff(unlessStill unchanged: Int? = nil) {
        diffTask?.cancel()
        diffLoadingTask?.cancel()
        guard let change = selectedChange, let repository else {
            shownDiff = nil
            return
        }
        if shownDiff == nil {
            shownDiff = ShownDiff(change: change, content: nil)
        } else if shownDiff?.change.id != change.id {
            // Another file's diff stays up a moment, and gives way to a loader only if this one is slow.
            diffLoadingTask = Task { [weak self] in
                try? await Task.sleep(for: Self.diffLoadingDelay)
                guard !Task.isCancelled, let self else { return }
                self.shownDiff = ShownDiff(change: change, content: nil)
            }
        }
        let expanded = expandedDiffID == change.id
        diffTask = Task { [weak self] in
            let loaded = await GitDiffContent.load(
                change, from: repository, expanded: expanded, unlessStill: unchanged)
            // Cancelled: a newer load replaced this one.
            guard !Task.isCancelled, let self else { return }
            self.diffTask = nil
            guard let loaded, self.selection == change.id else { return }
            self.diffLoadingTask?.cancel()
            self.shownDiff = ShownDiff(change: change, content: loaded.content, fingerprint: loaded.fingerprint)
        }
    }
}
