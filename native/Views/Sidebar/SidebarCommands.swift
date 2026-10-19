import NativeCommands
import TaskList

extension CommandID {
    static let sidebarSelectAll: Self = "sidebar.selectAll"
    static let sidebarSelectMode: Self = "sidebar.selectMode"
    static let selectionClear: Self = "selection.clear"
    static let selectionArchive: Self = "selection.archive"
    static let selectionUnarchive: Self = "selection.unarchive"
    static let selectionDelete: Self = "selection.delete"
    static let selectionMarkRead: Self = "selection.markRead"
    static let selectionMarkUnread: Self = "selection.markUnread"
    static let selectionPin: Self = "selection.pin"
    static let selectionUnpin: Self = "selection.unpin"
    static let selectionStop: Self = "selection.stop"
}

extension NativeCommand {
    /// Picking several tasks in the focused window's sidebar, and acting on all of them. Each bulk
    /// command is there while at least one picked task would change.
    static func sidebarSelection(model: AppModel) -> [NativeCommand] {
        func bulk(
            _ id: CommandID, _ title: String, systemImage: String, applies: @escaping (BulkTaskActions) -> Bool,
            perform: @escaping @MainActor (SidebarSelectionModel, CommandContext) -> Void
        ) -> NativeCommand {
            NativeCommand(id, title: title, category: .tasks, systemImage: systemImage, keywords: ["selected", "bulk"])
            {
                context in
                guard let selection = context.sidebarSelection, !selection.keys.isEmpty else { return }
                perform(selection, context)
            }
            .available { context in
                guard let keys = context.sidebarSelection?.keys, !keys.isEmpty else { return false }
                return applies(model.bulkAvailability(of: keys))
            }
        }

        return [
            NativeCommand(
                .sidebarSelectAll, title: "Select All Tasks in Project", category: .tasks,
                systemImage: "checklist", keywords: ["bulk", "pick"]
            ) { context in
                guard let selection = context.sidebarSelection else { return }
                selection.selectAll(model.selectAllTargets(after: selection))
            }
            .available { context in
                context.sidebarSelection.map { !model.selectAllTargets(after: $0).isEmpty } ?? false
            },

            NativeCommand(
                .sidebarSelectMode, title: "Select Tasks", category: .tasks, systemImage: "checkmark.circle",
                keywords: ["bulk", "pick", "multiple"]
            ) { context in
                context.sidebarSelection?.isSelecting.toggle()
            }
            .menuTitle { $0.sidebarSelection?.isSelecting == true ? "Done Selecting" : "Select Tasks" }
            .available { $0.sidebarSelection != nil && !model.sessionList.isEmpty },

            NativeCommand(.selectionClear, title: "Deselect Tasks", category: .tasks, systemImage: "xmark.circle") {
                $0.sidebarSelection?.clear()
            }
            .available { $0.sidebarSelection?.isActive == true },

            bulk(.selectionArchive, "Archive Selected Tasks", systemImage: "archivebox", applies: \.canArchive) {
                selection, context in
                let keys = selection.keys
                selection.clear()
                Task { await model.archiveSessions(keys, undoManager: context.undoManager) }
            },
            bulk(
                .selectionUnarchive, "Unarchive Selected Tasks", systemImage: "arrow.uturn.backward",
                applies: \.canUnarchive
            ) { selection, _ in
                let keys = selection.keys
                Task { await model.unarchiveSessions(keys) }
            },
            bulk(.selectionDelete, "Delete Selected Tasks…", systemImage: "trash", applies: { _ in true }) {
                selection, _ in
                selection.isConfirmingDelete = true
            },
            bulk(.selectionMarkRead, "Mark Selected as Read", systemImage: "envelope.open", applies: \.canMarkRead) {
                selection, _ in
                model.setUnread(selection.keys, false)
            },
            bulk(
                .selectionMarkUnread, "Mark Selected as Unread", systemImage: "envelope.badge",
                applies: \.canMarkUnread
            ) { selection, _ in
                model.setUnread(selection.keys, true)
            },
            bulk(.selectionPin, "Pin Selected Tasks", systemImage: "pin", applies: \.canPin) { selection, context in
                model.setPinned(selection.keys, true, undoManager: context.undoManager)
            },
            bulk(.selectionUnpin, "Unpin Selected Tasks", systemImage: "pin.slash", applies: \.canUnpin) {
                selection, context in
                model.setPinned(selection.keys, false, undoManager: context.undoManager)
            },
            bulk(.selectionStop, "Stop Selected Tasks", systemImage: "stop.circle", applies: \.canStop) {
                selection, _ in
                let keys = selection.keys
                Task { await model.stopSessions(keys) }
            },
        ]
    }
}

extension AppModel {
    /// What ⌘A picks in the sidebar: every task on screen in the project of the task open (or the
    /// last one picked); in the Pinned section, every pinned task.
    func selectAllTargets(after selection: SidebarSelectionModel) -> [SessionKey] {
        guard let key = selection.picked.anchor ?? self.selection, selection.order.contains(key) else { return [] }
        if isPinned(key) {
            return selection.order.filter(isPinned)
        }
        guard let project = catalog.lookup(key)?.project else { return [] }
        return selection.order.filter { !isPinned($0) && catalog.lookup($0)?.project == project }
    }
}
