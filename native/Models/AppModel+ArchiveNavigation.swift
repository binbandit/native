import ACP
import TaskList

extension AppModel {
    func setArchiveNavigationOrder(_ order: any ArchiveNavigationOrdering) {
        archiveNavigationOrder = order
    }

    /// Keep a task open when the selected one leaves, using the sidebar's order before it changes.
    /// The return value lets Undo reopen the task the user was looking at.
    @discardableResult
    func moveAfterArchiving(_ keys: [SessionKey]) -> SessionKey? {
        guard let selected = selection, keys.contains(selected) else { return nil }
        let order = archiveNavigationOrder?.archiveSessionOrder() ?? sessionList.map(\.id)
        if let next = TaskListNavigation.successor(to: selected, removing: Set(keys), in: order) {
            selection = next
        } else if let project = catalog.lookup(selected)?.project {
            focusProject(project)
        }
        return selected
    }

    func undoArchive(_ keys: [SessionKey], selecting selected: SessionKey?) {
        let restoring = keys.filter(beginUnarchiving)
        if let selected, restoring.contains(selected) {
            selection = selected
        }
        Task {
            for key in restoring {
                await finishUnarchiving(key)
            }
        }
    }
}
