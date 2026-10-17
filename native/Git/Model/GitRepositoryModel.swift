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
    private(set) var status: RepositoryStatus?
    /// Whether there's anywhere to push; publishing is only offered when there is.
    private(set) var hasRemote = false
    /// The change whose diff is showing.
    var selection: FileChange.ID? {
        didSet {
            if selection != oldValue { loadSelectedDiff() }
        }
    }
    private(set) var selectedDiff: GitDiffContent?
    /// A stage, commit or push is running.
    private(set) var isWorking = false
    /// Feedback for the last action: a failure with its next step, or a confirmation.
    private(set) var notice: GitNotice?
    /// The commit form's message, kept while the form is closed so a draft isn't lost.
    var commitMessage = ""

    @ObservationIgnored let resolveGit: () async -> Git?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshPending = false
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var selectedDiffID: FileChange.ID?

    /// How long file events settle before a rescan, so a burst of agent writes costs one scan.
    static let settleDelay = Duration.milliseconds(250)
    /// Beyond this many changed paths an event batch isn't worth checking against `.gitignore`.
    static let ignoreCheckLimit = 500
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
        selectedDiffID = selection
        selectedDiff = diff
    }

    deinit {
        refreshTask?.cancel()
        watchTask?.cancel()
        diffTask?.cancel()
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

    /// "main ↑2 ↓1 · 5 changed" for a window subtitle; `nil` outside a repository.
    var summary: String? {
        guard let branch else { return nil }
        var parts = [branch.displayName]
        if branch.ahead > 0 { parts[0] += " ↑\(branch.ahead)" }
        if branch.behind > 0 { parts[0] += " ↓\(branch.behind)" }
        if let status, !status.isClean { parts.append("\(status.changedFileCount) changed") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Refreshing

    /// Rescans soon. Calls while a scan runs coalesce into one more scan after it.
    func refresh() {
        requestRefresh(settling: false)
    }

    /// Rescans and waits for the result.
    func refreshNow() async {
        refresh()
        await refreshTask?.value
    }

    private func requestRefresh(settling: Bool) {
        isRefreshPending = true
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            if settling { try? await Task.sleep(for: Self.settleDelay) }
            while let self, self.isRefreshPending, !Task.isCancelled {
                self.isRefreshPending = false
                await self.load()
            }
            self?.refreshTask = nil
        }
    }

    private func load() async {
        do {
            guard let repository = try await currentRepository() else {
                state = .notRepository
                status = nil
                return
            }
            async let remotes = repository.remotes()
            let status = try await repository.status()
            hasRemote = !(try await remotes).isEmpty
            guard !Task.isCancelled else { return }
            apply(status)
            state = .ready
        } catch {
            // A failed rescan keeps the last good status on screen.
            if status == nil { state = .failed(error.localizedDescription) }
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
            previous?.changes.first(where: { $0.id == selected.id }) != selected || selectedDiff == nil
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
                if await self.matters(change, in: repository) {
                    self.requestRefresh(settling: true)
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

    private func loadSelectedDiff() {
        diffTask?.cancel()
        guard let change = selectedChange, let repository else {
            selectedDiff = nil
            selectedDiffID = nil
            return
        }
        // A different file shows as loading rather than under the previous file's diff.
        if selectedDiffID != change.id {
            selectedDiff = nil
            selectedDiffID = change.id
        }
        diffTask = Task { [weak self] in
            let content: GitDiffContent
            do {
                content = GitDiffContent(change: change, versions: try await repository.versions(of: change))
            } catch {
                content = .unavailable(error.localizedDescription)
            }
            guard !Task.isCancelled, let self, self.selection == change.id else { return }
            self.selectedDiff = content
        }
    }
}
