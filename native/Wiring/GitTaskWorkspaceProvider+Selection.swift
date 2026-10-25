import ACP
import Foundation
import Git

extension GitTaskWorkspaceProvider {
    func workspaceOptions(in project: Project, current: URL) async throws -> [TaskWorkspaceOption] {
        var options = [
            TaskWorkspaceOption(
                choice: .project, title: "Project Folder", detail: project.path,
                isCurrent: SessionFolder.isSame(current.folderPath, project.path))
        ]
        guard let repository = try await git.resolveGit().repository(at: project.url) else { return options }
        if try await repository.hasCommits() {
            options.append(
                TaskWorkspaceOption(
                    choice: .newWorktree, title: "New Worktree", detail: "A new branch in its own folder",
                    isCurrent: false))
        }
        let worktrees = try await repository.worktrees()
        for branch in try await repository.branches(includingRemote: false) {
            let checkout = worktrees.first { $0.branch == branch.name && !$0.isPrunable }
            options.append(
                TaskWorkspaceOption(
                    choice: .branch(branch.name), title: branch.name,
                    detail: checkout?.path.folderPath ?? "Create a worktree for this branch",
                    isCurrent: checkout.map { SessionFolder.isSame($0.path.folderPath, current.folderPath) } ?? false))
        }
        for worktree in worktrees where worktree.branch == nil && !worktree.isPrunable {
            options.append(
                TaskWorkspaceOption(
                    choice: .worktree(worktree.path), title: "Detached Worktree", detail: worktree.path.folderPath,
                    isCurrent: SessionFolder.isSame(worktree.path.folderPath, current.folderPath)))
        }
        return options
    }

    func newWorktreeStart(in project: Project) async throws -> TaskWorkspaceChoice? {
        guard let base = try await git.taskWorktreeStart(in: project.url) else { return nil }
        return .newWorktreeFrom(commit: base.commit, branch: base.branch, notice: base.localNotice)
    }

    func workspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> URL {
        try await prepareWorkspace(for: choice, in: project).folder
    }

    func prepareWorkspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> TaskWorkspacePreparation
    {
        switch choice {
        case .project:
            return .init(folder: project.url, createdForTask: false)
        case .newWorktree:
            let prefix = git.settings.branchPrefix(
                forProjectAt: project.url, gitHubLogin: await gitHubLogin(for: project))
            guard let checkout = try await git.prepareTaskCheckout(in: project.url, prefix: prefix, forceWorktree: true)
            else { throw TaskWorkspaceSelectionError("This folder is not a git repository. Use the project folder.") }
            return .init(folder: checkout.folder, createdForTask: true)
        case .newWorktreeFrom(let commit, let branch, let notice):
            let prefix = git.settings.branchPrefix(
                forProjectAt: project.url, gitHubLogin: await gitHubLogin(for: project))
            guard
                let checkout = try await git.prepareTaskCheckout(
                    in: project.url, prefix: prefix, forceWorktree: true,
                    startingAt: GitStore.PinnedStart(commit: commit, branch: branch, notice: notice))
            else { throw TaskWorkspaceSelectionError("This folder is not a git repository. Use the project folder.") }
            return .init(folder: checkout.folder, createdForTask: true)
        case .branch(let branch):
            let repository = try await git.requireRepository(at: project.url)
            // Never switch a checkout under another task. Reuse its exact folder when checked out.
            if let existing = try await repository.worktrees().first(where: { $0.branch == branch && !$0.isPrunable }) {
                return .init(folder: existing.path, createdForTask: false)
            }
            guard try await repository.hasBranch(branch) else {
                throw TaskWorkspaceSelectionError(
                    "That branch is no longer available. Close this picker and try again.")
            }
            let checkout = try await git.prepareTaskCheckout(in: project.url, existingBranch: branch)
            return .init(folder: checkout.folder, createdForTask: true)
        case .worktree(let folder):
            let repository = try await git.requireRepository(at: project.url)
            guard
                let existing = try await repository.worktrees().first(where: {
                    !$0.isPrunable && SessionFolder.isSame($0.path.folderPath, folder.folderPath)
                })
            else {
                throw TaskWorkspaceSelectionError("That worktree is no longer available. Choose another workspace.")
            }
            return .init(folder: existing.path, createdForTask: false)
        }
    }

    func removeUnusedWorkspace(at folder: URL, in project: Project) async throws -> Bool {
        guard !scripts.runs(in: folder).contains(where: { $0.isRunning || $0.state == .awaitingApproval })
        else { return false }
        let repository = try await git.requireRepository(at: project.url)
        guard let receipt = try await repository.unusedTaskWorktree(at: folder) else { return false }
        return try await repository.removeUnusedTaskWorktree(receipt)
    }
}
