import Foundation
import Git

/// New tasks' checkouts: a worktree (or a branch in the project's checkout) on a provisional
/// branch, set up from the project, then renamed after the task's title.
extension GitStore {
    /// Makes the checkout a new task runs in, following `settings`. A worktree gets the project's
    /// ignored env files before this returns, so the agent sees them from its first turn, and its
    /// setup scripts start in the background. `nil` when the project isn't a git repository.
    func prepareTaskCheckout(in project: URL, prefix: String) async throws -> GitTaskCheckout? {
        guard let repository = try await resolveGit().repository(at: project) else { return nil }
        let (branch, code) = try await provisionalBranch(in: repository, prefix: prefix)
        switch settings.newTaskWorkspace(forProjectAt: project) {
        case .branch:
            try await repository.createAndSwitchBranch(branch)
            try await repository.markProvisional(branch)
            model(for: repository.root).refresh()
            return GitTaskCheckout(folder: repository.root, branch: branch, copiedFiles: [])
        case .worktree:
            // A worktree branches from a commit; `git init` alone leaves nothing to branch from.
            guard try await repository.hasCommits() else { throw TaskWorkspaceError.noCommits }
            let folder = taskLocation(of: repository).appending(path: code, directoryHint: .isDirectory)
            let base = try? await repository.currentBranchName()
            let worktree: Worktree
            do {
                worktree = try await repository.addWorktree(at: folder, newBranch: branch)
            } catch {
                // A checkout that fails (no room, no permission) can leave the new branch behind. It
                // was free a moment ago, so it's this task's, and a retry makes another.
                try? await repository.deleteBranch(branch)
                throw error
            }
            try await repository.markProvisional(branch)
            return try await setUp(worktree, of: repository, branch: branch, baseBranch: base)
        }
    }

    /// A task worktree that checks out `branch`, which must exist (a pull request's head, fetched
    /// for it), named after it and set up like any new task's. The branch keeps its name.
    func prepareTaskCheckout(in project: URL, existingBranch branch: String) async throws -> GitTaskCheckout {
        let repository = try await requireRepository(at: project)
        let worktree = try await repository.createWorktree(
            checkingOut: branch, folderName: branch, in: worktreesBase(of: repository))
        return try await setUp(worktree, of: repository, branch: branch)
    }

    /// Copies the project's ignored env files into a new task worktree before returning, so the
    /// agent sees them from its first turn, then tells `onTaskWorktreeCreated`, which starts its
    /// setup scripts. Internal only for GitStore+ArchivedWorktrees.swift, which sets up a worktree
    /// it brings back the same way.
    func setUp(
        _ worktree: Worktree, of repository: Repository, branch: String, baseBranch: String? = nil
    ) async throws -> GitTaskCheckout {
        let main = try await repository.worktrees().first(where: \.isMain)?.path ?? repository.root
        var created = GitTaskWorktree(
            folder: worktree.path, projectRoot: main, branch: branch, baseBranch: baseBranch)
        do {
            created.copiedFiles = try await requireRepository(at: main).copyIgnoredFiles(
                matching: settings.envFilePatterns, to: worktree.path)
        } catch {
            created.copyFailure = error.localizedDescription
        }
        onTaskWorktreeCreated?(created)
        return GitTaskCheckout(folder: worktree.path, branch: branch, copiedFiles: created.copiedFiles)
    }

    /// Renames a task's provisional branch after its title, if the settings allow it and the
    /// branch hasn't been renamed or pushed. Generic titles ("New Session") are skipped.
    /// `suggestion` names it from the title and the provisional name's prefix instead, when it can.
    func renameProvisionalBranch(
        at folder: URL, title: String, suggestion: ((_ title: String, _ prefix: String) async -> String?)? = nil
    ) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.renamesBranches, !title.isEmpty, title != "New Task" else { return }
        let model = model(for: folder)
        if model.repository == nil { await model.refreshNow() }
        guard let repository = model.repository, let branch = model.branch?.name,
            (try? await repository.isRenamableProvisional(branch)) == true
        else { return }
        let prefix = BranchNaming.prefix(ofProvisional: branch)
        let name = await suggestion?(title, prefix) ?? BranchNaming.name(forTitle: title, prefix: prefix)
        if (try? await repository.renameProvisionalBranch(branch, to: name)) != nil {
            model.refresh()
        }
    }

    /// The worktrees Native made for the project's tasks, under `~/.native/worktrees/<repository>/`.
    /// The user's own worktrees elsewhere aren't included.
    func taskWorktrees(of project: URL) async -> [URL] {
        guard let repository = try? await resolveGit().repository(at: project),
            let worktrees = try? await repository.worktrees()
        else { return [] }
        let location = taskLocation(of: repository).standardizedFileURL.path(percentEncoded: false)
        // A record whose folder was deleted by hand isn't a worktree to list or remove.
        return worktrees.filter {
            !$0.isMain && !$0.isPrunable && $0.path.standardizedFileURL.path(percentEncoded: false).hasPrefix(location)
        }
        .map(\.path)
    }

    /// Whether `folder` is a worktree Native made, which Native may remove.
    func isTaskWorktree(_ folder: URL, of project: URL) async -> Bool {
        let path = folder.standardizedFileURL.path(percentEncoded: false)
        return await taskWorktrees(of: project).contains { $0.standardizedFileURL.path(percentEncoded: false) == path }
    }

    // MARK: - Helpers

    /// Where a repository's task worktrees go: a folder per repository in `worktreesBase(of:)`.
    func taskLocation(of repository: Repository) -> URL {
        worktreesBase(of: repository).appending(
            path: Worktree.slug(repository.name, maxLength: 60), directoryHint: .isDirectory)
    }

    /// Where task worktrees go, in the home folder of the machine the repository is on. On this Mac
    /// the `gitWorktreesFolder` default can move them, which isolated development instances use so
    /// their test worktrees never mix with real ones (scripts/dev/run-isolated.sh). A paired host's
    /// store uses the folder that host says (`HostProjectList.worktreesFolder`): its git runs with
    /// no `HOME` of this Mac's, which would otherwise read as this Mac.
    func worktreesBase(of repository: Repository) -> URL {
        if let worktreesFolder { return worktreesFolder }
        let home = repository.git.environment["HOME"]
        let isThisMac = home == nil || home == NSHomeDirectory()
        let override = isThisMac ? UserDefaults.standard.string(forKey: "gitWorktreesFolder") : nil
        return override.map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Worktree.defaultLocation(home: home)
    }

    /// `<prefix><code>` with a code no branch uses yet.
    private func provisionalBranch(in repository: Repository, prefix: String) async throws -> (String, String) {
        for _ in 0..<5 {
            let code = BranchNaming.provisionalCode()
            let branch = prefix + code
            if try await repository.uniqueBranchName(branch) == branch { return (branch, code) }
        }
        throw GitError.failed(arguments: ["branch"], status: 1, stderr: "Couldn't find a free branch name.")
    }
}
