import ACP
import Foundation

// Which project a session started outside the sidebar's New Task belongs to, so it starts on the
// project's model like the tasks the user starts there.
extension AppModel {
    /// The project `folder` belongs to: a session's project when it has one, else the project whose
    /// folder holds it, else the one whose task workspaces (worktrees made elsewhere) include it.
    func project(of session: SessionModel?, folder: URL) async -> Project.ID? {
        if let session, let project = catalog.lookup(session.root.key)?.project {
            return project
        }
        if let project = projects.all.first(where: { SessionFolder.contains($0.url.folderPath, folder.folderPath) }) {
            return project.id
        }
        for project in projects.all {
            let folders = await taskWorkspaces?.taskFolders(of: project) ?? []
            if folders.contains(where: { SessionFolder.contains($0.folderPath, folder.folderPath) }) {
                return project.id
            }
        }
        return nil
    }
}
