import Foundation
import Git
import Observation

/// Live git state for one working folder: branch, changes and the selected file's diff, kept fresh
/// by a file system watcher. Every git action the UI offers goes through this model.
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
    /// The change whose diff is showing.
    var selection: FileChange.ID? {
        didSet {
            if selection != oldValue { loadSelectedDiff() }
        }
    }
    private(set) var selectedDiff: GitDiffContent?
    /// A stage, commit or push is running.
    private(set) var isWorking = false
    /// The last action's failure, for the inspector to show until dismissed.
    var actionError: String?
    /// The commit form's message, kept while the form is closed so a draft isn't lost.
    var commitMessage = ""

    @ObservationIgnored let resolveGit: () async throws -> Git?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshPending = false
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var diffTask: Task<Void, Never>?
    @ObservationIgnored private var selectedDiffID: FileChange.ID?

    /// How long file events settle before a rescan, so a burst of agent writes costs one scan.
    static let settleDelay = Duration.milliseconds(250)
    /// Beyond this many changed paths an event batch isn't worth checking against `.gitignore`.
    static let ignoreCheckLimit = 500

    init(folder: URL, git: @escaping () async throws -> Git?) {
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
            let status = try await repository.status()
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
        guard let git = try await resolveGit(), let repository = try await git.repository(at: folder) else { return nil }
        self.repository = repository
        startWatching(repository)
        return repository
    }

    private func apply(_ newStatus: RepositoryStatus) {
        let previous = status
        guard newStatus != previous else { return }
        status = newStatus
        // Keep the same file selected when it moves between areas, e.g. after staging it.
        if let selected = previous?.changes.first(where: { $0.id == selection }), !newStatus.changes.contains(where: { $0.id == selection }) {
            selection = newStatus.changes.first { $0.path == selected.path }?.id ?? newStatus.changes.first?.id
        } else if selection == nil || !newStatus.changes.contains(where: { $0.id == selection }) {
            selection = newStatus.changes.first?.id
        }
        // The selected file itself may have changed on disk.
        if let selected = selectedChange, previous?.changes.first(where: { $0.id == selected.id }) != selected || selectedDiff == nil {
            loadSelectedDiff()
        }
    }

    // MARK: - Actions

    func stage(_ changes: [FileChange]) async {
        await perform { try await $0.stage(Self.paths(of: changes)) }
    }

    func unstage(_ changes: [FileChange]) async {
        await perform { try await $0.unstage(Self.paths(of: changes)) }
    }

    /// Destructive: the caller confirms first. The current files go to the Trash.
    func discard(_ changes: [FileChange]) async {
        await perform { try await $0.discard(changes) }
    }

    func push() async {
        await perform { try await $0.push() }
    }

    /// Commits exactly `files`, staging them and unstaging anything else, then pushes if asked.
    /// A failed commit throws so the commit form can show git's output (often a hook's); a failed
    /// push after a good commit lands in `actionError`, since the commit itself happened.
    func commit(message: String, files: [FileChange], push: Bool) async throws {
        guard let repository else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.commit(message: message, files: files)
        } catch {
            await refreshNow()
            throw error
        }
        commitMessage = ""
        if push {
            do {
                try await repository.push()
            } catch {
                actionError = "Committed, but the push failed: \(error.localizedDescription)"
            }
        }
        await refreshNow()
    }

    /// A commit message for `files` from the on-device model, in the style of recent commits.
    func draftCommitMessage(for files: [FileChange]) async throws -> String {
        guard let repository else { return "" }
        async let patch = repository.patch(for: files)
        async let subjects = repository.recentCommitSubjects()
        return try await CommitMessageDrafter().draft(patch: patch, files: files, style: CommitStyle(subjects: subjects))
    }

    private func perform(_ action: (Repository) async throws -> Void) async {
        guard let repository, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await action(repository)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
        await refreshNow()
    }

    /// Every path the changes touch, renames' original paths included.
    private static func paths(of changes: [FileChange]) -> [String] {
        Array(Set(changes.flatMap(\.paths))).sorted()
    }

    // MARK: - Watching

    private func startWatching(_ repository: Repository) {
        guard watchTask == nil, let watcher = RepositoryWatcher(repository: repository) else { return }
        watchTask = Task { [weak self] in
            for await change in watcher.changes {
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
