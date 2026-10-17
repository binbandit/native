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

    @ObservationIgnored private let environmentProvider: EnvironmentProvider
    @ObservationIgnored private var git: Git?
    // Not observed: models are created lazily from view bodies, which mustn't mutate observed state.
    @ObservationIgnored private var models: [URL: GitRepositoryModel] = [:]

    init(environment: @escaping EnvironmentProvider = { await LoginShell.environment() }) {
        environmentProvider = environment
    }

    /// The model for the working tree containing `folder`. It starts loading and watching right away.
    func model(for folder: URL) -> GitRepositoryModel {
        let key = folder.standardizedFileURL
        if let model = models[key] { return model }
        let model = GitRepositoryModel(folder: key, git: { [weak self] in try await self?.resolveGit() })
        models[key] = model
        return model
    }

    /// Re-reads a folder's status, e.g. after an agent finished a turn there. Folders nobody has
    /// asked about yet are skipped.
    func refresh(folder: URL) {
        models[folder.standardizedFileURL]?.refresh()
    }

    func refreshAll() {
        models.values.forEach { $0.refresh() }
    }

    // MARK: - Task worktrees

    /// Gives a new task its own worktree of the repository at `folder`, on a new branch from its
    /// current HEAD, and returns the worktree's folder to run the session in.
    func createTaskWorktree(in folder: URL, title: String, branchPrefix: String = "") async throws -> URL {
        let repository = try await requireRepository(at: folder)
        let worktree = try await repository.createWorktree(forTask: title, branchPrefix: branchPrefix)
        return worktree.path
    }

    /// Removes a task's worktree, first saving uncommitted work under `refs/native-checkpoints/`.
    /// Its branch stays. Returns the checkpoint ref when there was work to save.
    @discardableResult
    func removeTaskWorktree(at folder: URL) async throws -> String? {
        let repository = try await requireRepository(at: folder)
        let checkpoint = try await repository.removeWorktree(at: repository.root, force: true)
        models.removeValue(forKey: folder.standardizedFileURL)
        return checkpoint?.reference
    }

    // MARK: - Resolving git

    private func resolveGit() async throws -> Git {
        if let git { return git }
        let resolved = try Git(environment: await environmentProvider())
        git = resolved
        return resolved
    }

    private func requireRepository(at folder: URL) async throws -> Repository {
        guard let repository = try await resolveGit().repository(at: folder) else {
            throw GitError.failed(arguments: ["rev-parse"], status: 128, stderr: "\(folder.path(percentEncoded: false)) isn't in a git repository.")
        }
        return repository
    }
}
