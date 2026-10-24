import Foundation
import Git
import NativePolicy
import Observation

#if os(macOS)
import UserShell
#endif

/// The app's entry point to git: one live `GitRepositoryModel` per working folder, shared by the
/// inspector, the toolbar summary and sidebar badges so a folder is only watched and scanned once.
@Observable
final class GitStore {
    /// Where the user's shell environment comes from: git and its helpers need the user's PATH,
    /// which a GUI app doesn't inherit.
    typealias EnvironmentProvider = () async -> [String: String]

    let settings: GitSettings
    /// How each task turn's working tree looked as it began, for reviewing what the turn changed.
    @ObservationIgnored let turnBaselines: GitTurnBaselines
    /// Told about every push Native makes, with the checkout it ran in and the branch, e.g. for
    /// "branch pushed" automations. Set by the app's wiring so Git doesn't know who listens.
    @ObservationIgnored var onBranchPushed: (@MainActor (_ project: URL, _ branch: String) -> Void)?
    /// Told about each task worktree Native makes, once its env files are copied, so its setup
    /// scripts can start. Set by the app's wiring so Git doesn't know who runs them.
    @ObservationIgnored var onTaskWorktreeCreated: (@MainActor (GitTaskWorktree) -> Void)?
    @ObservationIgnored var beforeCreatingTaskWorktree: (@MainActor (GitTaskWorktree) async throws -> Void)?
    @ObservationIgnored var allowsWorktreeFetch: () -> Bool = { PolicyCenter.shared.policy.worktreeFetchEnabled }
    /// Awaited before Native removes a task worktree, for its teardown scripts. It never stops the
    /// removal.
    @ObservationIgnored var beforeRemovingTaskWorktree: (@MainActor (GitTaskWorktree) async -> Void)?

    /// Where task worktrees go for a store whose projects are on a paired host; nil on this Mac,
    /// where `worktreesBase(of:)` works it out.
    let worktreesFolder: URL?
    /// Only local repositories may hand file URLs to this machine's openers.
    let isLocal: Bool
    @ObservationIgnored private let environmentProvider: EnvironmentProvider
    /// Builds git for the host the projects are on; a client passes one that runs on its host.
    @ObservationIgnored private let makeGit: ([String: String]) -> Git
    @ObservationIgnored private var git: Git?
    // Not observed: models are created lazily from view bodies, which mustn't mutate observed state.
    @ObservationIgnored private var models: [URL: GitRepositoryModel] = [:]
    @ObservationIgnored private var unavailableModels: [URL: GitRepositoryModel] = [:]

    init(
        environment: @escaping EnvironmentProvider, settings: GitSettings = GitSettings(),
        worktreesFolder: URL? = nil, isLocal: Bool = true, turnBaselines: GitTurnBaselines = .shared,
        makeGit: @escaping ([String: String]) -> Git
    ) {
        environmentProvider = environment
        self.settings = settings
        self.turnBaselines = turnBaselines
        self.worktreesFolder = worktreesFolder
        self.isLocal = isLocal
        self.makeGit = makeGit
    }

    #if os(macOS)
    /// Git on this Mac.
    convenience init(
        environment: @escaping EnvironmentProvider = { await LoginShell.environment() },
        settings: GitSettings = GitSettings()
    ) {
        self.init(environment: environment, settings: settings, makeGit: { Git(environment: $0) })
    }
    #endif

    /// Selects by session identity, never by path: different machines can use the same path.
    /// Nil from the resolver means the session's host is unavailable, not a local fallback.
    @ObservationIgnored var sessionStore: ((SessionKey) -> GitStore?)?

    private func owner(for session: SessionKey?) -> GitStore? {
        guard let session, let sessionStore else { return self }
        return sessionStore(session)
    }

    /// The model for the working tree containing `folder`. It starts loading and watching right away.
    func model(for folder: URL, session: SessionKey? = nil) -> GitRepositoryModel {
        guard let owner = owner(for: session) else {
            let key = folder.standardizedFileURL
            if let model = unavailableModels[key] { return model }
            let model = GitRepositoryModel(unavailableFolder: key)
            unavailableModels[key] = model
            return model
        }
        if owner !== self { return owner.model(for: folder) }
        let key = folder.standardizedFileURL
        if let model = models[key] { return model }
        let model = GitRepositoryModel(folder: key, isLocal: isLocal, git: { [weak self] in await self?.resolveGit() })
        model.onPushed = { [weak self] project, branch in self?.onBranchPushed?(project, branch) }
        models[key] = model
        return model
    }

    /// Already loaded local state for passive previews. This never starts a watcher or a host request.
    func availableLocalRepository(for folder: URL) -> Repository? {
        guard isLocal else { return nil }
        return models[folder.standardizedFileURL]?.repository
    }

    /// Re-reads a folder's status, e.g. after an agent finished a turn there. Folders nobody has
    /// asked about yet are skipped.
    func refresh(folder: URL, session: SessionKey? = nil) {
        guard let owner = owner(for: session) else { return }
        if owner !== self { return owner.refresh(folder: folder) }
        models[folder.standardizedFileURL]?.refresh()
    }

    /// Re-reads a folder's status once a burst of writes there settles, e.g. an agent's edits;
    /// the folder's own file events coalesce into the same rescan.
    func refreshWhenSettled(folder: URL, session: SessionKey? = nil) {
        guard let owner = owner(for: session) else { return }
        if owner !== self { return owner.refreshWhenSettled(folder: folder) }
        models[folder.standardizedFileURL]?.refreshWhenSettled()
    }

    func refreshAll() {
        models.values.forEach { $0.refresh() }
    }

    /// Records how `folder` looked as a task's turn began there (`GitTurnBaselines`), in the
    /// background, so sending the prompt never waits on it. Folders outside git are skipped.
    func recordTurnStart(of session: SessionKey, at startedAt: Date, in folder: URL) {
        guard let owner = owner(for: session) else { return }
        if owner !== self { return owner.recordTurnStart(of: session, at: startedAt, in: folder) }
        Task(priority: .utility) {
            guard let repository = try? await resolveGit().repository(at: folder) else { return }
            await turnBaselines.record(session, startedAt: startedAt, in: repository)
        }
    }

    // MARK: - Task worktrees

    /// Gives a new task its own worktree of the repository at `folder`, on a new branch from its
    /// latest remote base when available, and returns its folder to run the task in.
    func createTaskWorktree(in folder: URL, title: String, branchPrefix: String = "") async throws -> URL {
        let repository = try await requireRepository(at: folder)
        let main = try await repository.worktrees().first(where: \.isMain)?.path ?? repository.root
        try await beforeCreatingTaskWorktree?(GitTaskWorktree(folder: repository.root, projectRoot: main, branch: nil))
        let base = try await repository.taskWorktreeBase(fetchRemote: allowsWorktreeFetch())
        let worktree = try await repository.createWorktree(
            forTask: title, branchPrefix: branchPrefix, startPoint: base.commit, in: worktreesBase(of: repository))
        if let branch = worktree.branch {
            _ = try await setUp(
                worktree, of: repository, branch: branch, baseBranch: base.branch, baseNotice: base.localNotice)
        }
        return worktree.path
    }

    /// Removes a task's worktree, first saving its uncommitted work as a checkpoint. Its branch
    /// stays (or a copy of it, when the settings delete branches on archive). With `keepingRecord`,
    /// what brings it back is recorded in the repository before anything is removed, for
    /// `restoreArchivedTaskWorktree` in this run of Native or a later one.
    func removeTaskWorktree(at folder: URL, keepingRecord: Bool = false) async throws -> RemovedTaskWorktree {
        let repository = try await requireRepository(at: folder)
        let main = try await repository.worktrees().first(where: \.isMain)?.path ?? repository.root
        let branch = try await repository.status().branch.name
        await beforeRemovingTaskWorktree?(GitTaskWorktree(folder: repository.root, projectRoot: main, branch: branch))
        let checkpoint = try await repository.checkpoint(named: repository.root.lastPathComponent)
        if keepingRecord, let branch {
            try await requireRepository(at: main).recordArchivedWorktree(
                ArchivedWorktree(path: repository.root, branch: branch, checkpoint: checkpoint))
        }
        try await repository.removeWorktree(at: repository.root, force: true, checkpoint: false)
        models.removeValue(forKey: folder.standardizedFileURL)
        var archivedBranch = false
        if settings.deletesBranchOnArchive(forProjectAt: main), let branch {
            // The checkpoint, if any, sits on the branch's tip, so archiving keeps both reachable.
            archivedBranch = (try? await requireRepository(at: main).archiveBranch(branch)) != nil
        }
        return RemovedTaskWorktree(
            path: repository.root, branch: branch, checkpoint: checkpoint, archivedBranch: archivedBranch)
    }

    // MARK: - Resolving git

    func resolveGit() async -> Git {
        if let git { return git }
        let resolved = makeGit(await environmentProvider())
        git = resolved
        return resolved
    }

    func requireRepository(at folder: URL) async throws -> Repository {
        guard let repository = try await resolveGit().repository(at: folder) else {
            throw GitError.failed(
                arguments: ["rev-parse"], status: 128,
                stderr: "\(folder.path(percentEncoded: false)) isn't in a git repository.")
        }
        return repository
    }
}
