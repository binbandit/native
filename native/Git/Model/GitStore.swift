import Foundation
import Git
import Observation

/// The app's entry point to git: one live `GitRepositoryModel` per working folder, shared by the
/// inspector, the toolbar summary and sidebar badges so a folder is only watched and scanned once.
@Observable
final class GitStore {
    /// Where the user's shell environment comes from: git and its helpers need the user's PATH,
    /// which a GUI app doesn't inherit.
    typealias EnvironmentProvider = () async -> [String: String]

    let settings: GitSettings
    /// Told about every push Native makes, with the checkout it ran in and the branch, e.g. for
    /// "branch pushed" automations. Set by the app's wiring so Git doesn't know who listens.
    @ObservationIgnored var onBranchPushed: (@MainActor (_ project: URL, _ branch: String) -> Void)?
    /// Told about each task worktree Native makes, once its env files are copied, so its setup
    /// scripts can start. Set by the app's wiring so Git doesn't know who runs them.
    @ObservationIgnored var onTaskWorktreeCreated: (@MainActor (GitTaskWorktree) -> Void)?
    /// Awaited before Native removes a task worktree, for its teardown scripts. It never stops the
    /// removal.
    @ObservationIgnored var beforeRemovingTaskWorktree: (@MainActor (GitTaskWorktree) async -> Void)?

    @ObservationIgnored private let environmentProvider: EnvironmentProvider
    /// Builds git for the host the projects are on; a client passes one that runs on its host.
    @ObservationIgnored private let makeGit: ([String: String]) -> Git
    @ObservationIgnored private var git: Git?
    // Not observed: models are created lazily from view bodies, which mustn't mutate observed state.
    @ObservationIgnored private var models: [URL: GitRepositoryModel] = [:]

    init(
        environment: @escaping EnvironmentProvider, settings: GitSettings = GitSettings(),
        makeGit: @escaping ([String: String]) -> Git
    ) {
        environmentProvider = environment
        self.settings = settings
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

    /// The model for the working tree containing `folder`. It starts loading and watching right away.
    func model(for folder: URL) -> GitRepositoryModel {
        let key = folder.standardizedFileURL
        if let model = models[key] { return model }
        let model = GitRepositoryModel(folder: key, git: { [weak self] in await self?.resolveGit() })
        model.onPushed = { [weak self] project, branch in self?.onBranchPushed?(project, branch) }
        models[key] = model
        return model
    }

    /// Re-reads a folder's status, e.g. after an agent finished a turn there. Folders nobody has
    /// asked about yet are skipped.
    func refresh(folder: URL) {
        models[folder.standardizedFileURL]?.refresh()
    }

    /// Re-reads a folder's status once a burst of writes there settles, e.g. an agent's edits;
    /// the folder's own file events coalesce into the same rescan.
    func refreshWhenSettled(folder: URL) {
        models[folder.standardizedFileURL]?.refreshWhenSettled()
    }

    func refreshAll() {
        models.values.forEach { $0.refresh() }
    }

    // MARK: - Task worktrees

    /// Gives a new task its own worktree of the repository at `folder`, on a new branch from its
    /// current HEAD, and returns the worktree's folder to run the session in.
    func createTaskWorktree(in folder: URL, title: String, branchPrefix: String = "") async throws -> URL {
        let repository = try await requireRepository(at: folder)
        let worktree = try await repository.createWorktree(
            forTask: title, branchPrefix: branchPrefix, in: Self.worktreesBase(of: repository))
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
            path: repository.root, mainRoot: main, branch: branch, checkpoint: checkpoint,
            archivedBranch: archivedBranch)
    }

    /// Checks a removed task worktree's branch out where it was and restores its uncommitted work.
    func restoreTaskWorktree(_ removed: RemovedTaskWorktree) async throws -> URL {
        guard let branch = removed.branch else {
            throw GitError.detachedHead
        }
        let main = try await requireRepository(at: removed.mainRoot)
        var restoresBranch = removed.archivedBranch
        // Clean Up Merged may have deleted the branch since, keeping a copy the same way.
        if !restoresBranch, try await main.hasArchivedBranch(branch), try await !main.hasBranch(branch) {
            restoresBranch = true
        }
        if restoresBranch {
            try await main.restoreArchivedBranch(branch)
        }
        return try await main.restoreWorktree(at: removed.path, branch: branch, from: removed.checkpoint).path
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
