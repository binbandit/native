import SwiftUI

/// The bulk actions for the picked tasks, as menu items: a picked row's context menu and the
/// selection bar's More menu show these. Only what changes at least one task is offered, and the
/// titles say how many tasks it acts on.
struct SidebarBulkMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let selection: SidebarSelectionModel

    var body: some View {
        let keys = selection.keys
        let actions = model.bulkAvailability(of: keys)
        let count = "\(keys.count) \(keys.count == 1 ? "Task" : "Tasks")"
        if actions.canMarkRead {
            Button("Mark \(count) as Read", systemImage: "envelope.open") { model.setUnread(keys, false) }
        }
        if actions.canMarkUnread {
            Button("Mark \(count) as Unread", systemImage: "envelope.badge") { model.setUnread(keys, true) }
        }
        if actions.canPin {
            Button("Pin \(count)", systemImage: "pin") { model.setPinned(keys, true, undoManager: undoManager) }
        }
        if actions.canUnpin {
            Button("Unpin \(count)", systemImage: "pin.slash") {
                model.setPinned(keys, false, undoManager: undoManager)
            }
        }
        if actions.canStop {
            Divider()
            Button("Stop \(count)", systemImage: "stop.circle") { Task { await model.stopSessions(keys) } }
        }
        Divider()
        if actions.canArchive {
            Button("Archive \(count)", systemImage: "archivebox") {
                selection.clear()
                Task { await model.archiveSessions(keys, undoManager: undoManager) }
            }
        }
        if actions.canUnarchive {
            Button("Unarchive \(count)", systemImage: "arrow.uturn.backward") {
                Task { await model.unarchiveSessions(keys) }
            }
        }
        Button("Delete \(count)…", systemImage: "trash", role: .destructive) { selection.isConfirmingDelete = true }
        Divider()
        Button("Deselect All", systemImage: "xmark.circle") { selection.clear() }
    }
}

#if DEBUG
#Preview("Bulk menu") {
    let app = AppModel.preview()
    let selection = SidebarSelectionModel()
    selection.selectAll(SidebarPreviewFixtures.sessions(in: app).map(\.id))
    return DSPreviewPair {
        // The menu a row's context menu shows while several tasks are picked.
        Menu("4 Tasks") {
            SidebarBulkMenu(selection: selection)
        }
        .fixedSize()
    }
    .sidebarPreviewEnvironment(app)
}
#endif
