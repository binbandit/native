import Foundation
import TaskList

extension AppModel {
    /// Deleting agent history forgets the host record. Confirm closure and finish private-file
    /// cleanup first, while a refusal can still leave the task listed and openable for retry.
    func removePrivateTaskFiles(using route: TaskActionRoute) async -> Bool {
        let source = session(route.key)
        source?.isChangingWorkspace = true
        defer { source?.isChangingWorkspace = false }
        do {
            try await closeForScratchCleanup(route.key)
            try scratchTasks.delete(NoProjectLocation.key(route.key))
            return true
        } catch {
            actionFailure = ActionFailure(
                "Couldn't Delete Task",
                "\(error.localizedDescription) The task is still listed. Open it and try deleting it again."
            )
            return false
        }
    }
}
