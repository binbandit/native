import Foundation

@testable import Native

@MainActor
final class RecordingWorkspaces: TaskWorkspaceProvider {
    struct Call: Equatable {
        let operation: String
        let folder: String
        let project: String
    }
    var calls: [Call] = []
    var failsDeletion = false
    var holdArchive = false
    var pendingArchive: CheckedContinuation<Void, Never>?
    var holdPreparation = false
    var pendingPreparation: CheckedContinuation<URL, Never>?

    func record(_ operation: String, _ folder: URL, _ project: Project) {
        calls.append(Call(operation: operation, folder: folder.folderPath, project: project.path))
    }
    func workspaceOptions(in project: Project, current: URL) async throws -> [TaskWorkspaceOption] { [] }
    func workspace(for choice: TaskWorkspaceChoice, in project: Project) async throws -> URL { project.url }
    func removeUnusedWorkspace(at folder: URL, in project: Project) async throws -> Bool { false }
    func workspace(forNewTaskIn project: Project, title: String?) async throws -> URL {
        if holdPreparation { return await withCheckedContinuation { pendingPreparation = $0 } }
        return project.url
    }
    func newTaskWorkspaceLabel(in project: Project) -> String { "Fixture" }
    func archiveWorkspace(at folder: URL, in project: Project) async throws -> String? {
        record("archive", folder, project)
        if holdArchive { await withCheckedContinuation { pendingArchive = $0 } }
        return "Saved fixture checkpoint."
    }
    func restoreWorkspace(at folder: URL, in project: Project, task: ArchivedTaskDetails?) async throws -> Bool {
        record("restore", folder, project)
        return true
    }
    func restoreRemovedWorkspace(at folder: URL, branch: String, in project: Project) async throws {
        record("restoreRemoved", folder, project)
    }
    func deleteWorkspace(at folder: URL, in project: Project) async throws {
        record("delete", folder, project)
        if failsDeletion { throw RoutingFailure("Fixture workspace is still on disk") }
    }
    func taskWasDeleted(_ task: SessionKey, title: String, folder: URL, in project: Project) async {
        record("deleted", folder, project)
    }
    func taskDidGetTitle(_ title: String, request: String?, workspace: URL, in project: Project) async {}
    func archivedWorkspaceFolders(of project: Project) async -> [URL] { [] }
    func removedWorkspaces(
        among tasks: [(folder: URL, title: String)], in project: Project
    ) async -> [URL: RemovedWorkspace.Fate] { [:] }
    func deleteWorkspaces(of project: Project) async throws {}
    func taskFolders(of project: Project) async -> [URL] { [] }
}
