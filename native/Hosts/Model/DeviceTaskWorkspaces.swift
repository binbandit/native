import Foundation

/// Task workspaces on whichever device a task runs on: this Mac's for this Mac's folders, and each
/// paired host's own (the Git feature with its git running on the host) for folders on that host.
/// `AppModel.taskWorkspaces` is this, so archiving, restoring and deleting a task on a host puts
/// away its worktree there, exactly as for a task here. A folder is a host's when it's inside that
/// host's worktrees folder or is one of its checkouts; everything else is this Mac's.
final class DeviceTaskWorkspaces: TaskWorkspaceProvider {
    let local: any TaskWorkspaceProvider
    private weak var model: AppModel?

    init(local: any TaskWorkspaceProvider, model: AppModel) {
        self.local = local
        self.model = model
    }

    /// The host provider for `folder` and the project as that host has it, when `folder` is on a
    /// paired host.
    private func remote(_ folder: URL, in project: Project) -> (any TaskWorkspaceProvider, Project)? {
        guard let model, model.offersRemoteHosts else { return nil }
        let path = folder.folderPath
        for host in model.hosts.all {
            guard let provider = host.taskWorkspaces,
                let checkout = project.checkoutPath(on: .remote(host.id))
            else { continue }
            if host.isTaskFolder(path, ofCheckoutAt: checkout) {
                return (provider, project.onHost(at: checkout))
            }
        }
        return nil
    }

    // New tasks here; a host's are made through its own provider (AppModel+HostsStarting.swift).
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL {
        try await local.workspace(forNewTaskIn: project, title: title)
    }

    func newTaskWorkspaceLabel(in project: Project) -> String {
        local.newTaskWorkspaceLabel(in: project)
    }

    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String? {
        if let (provider, onHost) = remote(folder, in: project) {
            return try await provider.archiveWorkspace(at: folder, in: onHost)
        }
        return try await local.archiveWorkspace(at: folder, in: project)
    }

    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool {
        if let (provider, onHost) = remote(folder, in: project) {
            return try await provider.restoreWorkspace(at: folder, in: onHost, task: task)
        }
        return try await local.restoreWorkspace(at: folder, in: project, task: task)
    }

    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws {
        if let (provider, onHost) = remote(folder, in: project) {
            return try await provider.restoreRemovedWorkspace(at: folder, branch: branch, in: onHost)
        }
        try await local.restoreRemovedWorkspace(at: folder, branch: branch, in: project)
    }

    func deleteWorkspace(at folder: URL, in project: Project) async throws {
        if let (provider, onHost) = remote(folder, in: project) {
            return try await provider.deleteWorkspace(at: folder, in: onHost)
        }
        try await local.deleteWorkspace(at: folder, in: project)
    }

    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async {
        if let (provider, onHost) = remote(workspace, in: project) {
            return await provider.taskDidGetTitle(title, request: request, workspace: workspace, in: onHost)
        }
        await local.taskDidGetTitle(title, request: request, workspace: workspace, in: project)
    }

    func taskWasDeleted(_ task: SessionKey, title: String, folder: URL, in project: Project) async {
        if let (provider, onHost) = remote(folder, in: project) {
            return await provider.taskWasDeleted(task, title: title, folder: folder, in: onHost)
        }
        await local.taskWasDeleted(task, title: title, folder: folder, in: project)
    }

    // Whole-project questions are about this Mac's folders: a host's sessions are listed from the
    // host itself (AppModel+HostsSessions.swift), never by this Mac's agents.
    func archivedWorkspaceFolders(of project: Project) async -> [URL] {
        await local.archivedWorkspaceFolders(of: project)
    }

    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate] {
        await local.removedWorkspaces(among: tasks, in: project)
    }

    func deleteWorkspaces(of project: Project) async throws {
        try await local.deleteWorkspaces(of: project)
    }

    func taskFolders(of project: Project) async -> [URL] {
        await local.taskFolders(of: project)
    }
}

extension Project {
    /// The same project as a paired host has it: its checkout there as the folder, for the host's
    /// own task workspaces.
    func onHost(at path: String) -> Project {
        Project(
            id: id, url: URL(filePath: path, directoryHint: .isDirectory), displayName: displayName,
            repository: repository, remoteURL: remoteURL)
    }
}
