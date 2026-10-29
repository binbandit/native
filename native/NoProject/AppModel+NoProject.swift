import ACP
import Foundation
import TaskList

extension AppModel {
    var taskGroups: [Project] {
        let group = NoProjectLocation.group
        let hasTasks = allSessions(in: group.id).contains { !earlierConversations.isSetAside($0.id) }
        let showsGroup = hasTasks || !startingTasks(in: group.id).isEmpty || !problems.list(for: group.id).isEmpty
        return (showsGroup ? [group] : []) + projects.all
    }

    var noProjectDeviceOption: SessionDeviceOption {
        SessionDeviceOption(
            device: .thisMac, name: "This Mac", availability: .online,
            checkout: .present(path: NoProjectLocation.root.path))
    }

    func retainPrivateFiles(of source: SessionModel, for key: SessionKey) {
        guard let folder = scratchTasks.folder(for: NoProjectLocation.key(source.key)) else { return }
        do { try scratchTasks.reassign(folder, to: NoProjectLocation.key(key)) } catch {
            actionFailure = ActionFailure("Couldn't update private task files", error.localizedDescription)
        }
    }

    /// Startup may still be opening the agent after the row is discarded. Keep its working
    /// directory until that operation returns and the resulting session has closed.
    func finishDiscardingPrivateTask(_ task: StartingTask, session: SessionModel?) async {
        do {
            if let session { try await closeForScratchCleanup(session.key) }
            removeWorkspace(of: task)
        } catch {
            actionFailure = ActionFailure("Couldn't remove private task files", error.localizedDescription)
        }
    }

    func chooseNoProject() {
        guard !composeTask.isHeld else { return }
        quickEntry.project = nil
        quickEntry.device = .thisMac
        quickEntry.failure = nil
        quickEntry.picker = nil
        reconcileQuickEntryAgent()
        if composeTask.isPresented { prepareComposeEditor() }
    }

    func requestMoveToProject(_ key: SessionKey) {
        guard catalog.lookup(key)?.project == NoProjectLocation.id, !earlierConversations.isSetAside(key) else {
            return
        }
        movingProjectlessTask = key
    }
}
