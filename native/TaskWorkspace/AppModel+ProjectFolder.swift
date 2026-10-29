import ACP
import Foundation

extension AppModel {
    func preferredTaskWorkspace(in project: Project.ID) -> TaskWorkspaceChoice? {
        switch defaults.string(forKey: "projectDefaults.\(project.uuidString).folder") {
        case "project": .project
        case "separate": .newWorktree
        default: nil
        }
    }

    func rememberTaskWorkspace(_ choice: TaskWorkspaceChoice, in project: Project.ID) {
        let value: String
        switch choice {
        case .project: value = "project"
        case .newWorktree: value = "separate"
        default: return
        }
        defaults.set(value, forKey: "projectDefaults.\(project.uuidString).folder")
    }

    func usesProjectFolder(_ key: SessionKey) -> Bool {
        guard let listed = catalog.lookup(key), listed.project != NoProjectLocation.id,
            let project = projects.project(listed.project)
                ?? projects.archived.first(where: { $0.id == listed.project }),
            let path = project.checkoutPath(on: device(of: key))
        else { return false }
        let folder = session(key)?.cwd.folderPath ?? listed.info.cwd
        return SessionFolder.isSame(folder, path)
    }

    /// Only tasks on the same machine share files, even when two hosts use the same path.
    func projectFolderNote(
        in project: Project.ID, on device: SessionDevice, excluding key: SessionKey? = nil
    ) -> String? {
        let shares = sessions(in: project).contains { summary in
            summary.id != key && self.device(of: summary.id) == device && !isArchived(summary.id)
                && !pendingDeletionKeys.contains(summary.id) && usesProjectFolder(summary.id)
                && session(summary.id)?.canCancel == true
        }
        return shares ? "Another running task uses this folder. You would edit the same files." : nil
    }

    func chooseComposeWorkspace(_ choice: TaskWorkspaceChoice) {
        guard !composeTask.isHeld, composeTask.stage == .writing, composeTask.second == nil else { return }
        composeTask.workspace = choice
        if let project = quickEntry.project { rememberTaskWorkspace(choice, in: project) }
    }
}
