import Foundation
import Git

// What scripts that run around tasks need from git: which project a folder belongs to, and
// throwaway worktrees for trying a script out.
extension GitStore {
    /// The main checkout of the repository `folder` is in, and the branch checked out in `folder`.
    /// Nil outside a repository.
    func checkout(of folder: URL) async -> (main: URL, branch: String?)? {
        guard let repository = try? await resolveGit().repository(at: folder) else { return nil }
        let main = (try? await repository.worktrees().first(where: \.isMain)?.path) ?? repository.root
        return (main, try? await repository.currentBranchName())
    }

    /// A detached worktree of the project at `project`, with its env files copied in like a task's,
    /// for running a script once. Returns its folder and the branch it was made from.
    func makeScratchWorktree(of project: URL) async throws -> (folder: URL, baseBranch: String?) {
        let repository = try await requireRepository(at: project)
        let base = try? await repository.currentBranchName()
        let worktree = try await repository.createWorktree(
            forTask: "script-test", in: Self.worktreesBase(of: repository), detached: true)
        _ = try? await repository.copyIgnoredFiles(matching: settings.envFilePatterns, to: worktree.path)
        return (worktree.path, base)
    }

    /// Removes a scratch worktree for good, with no checkpoint: nothing in it is the user's.
    func removeScratchWorktree(at folder: URL) async {
        guard let repository = try? await requireRepository(at: folder) else { return }
        _ = try? await repository.removeWorktree(at: repository.root, force: true, checkpoint: false)
    }
}
