import SwiftUI
import TaskList

struct SidebarFolderRecentMenu: View {
    let model: AppModel
    let undoManager: UndoManager?

    var body: some View {
        ForEach(model.sidebarFolders.history.entries) { entry in
            Button("\(entry.url.lastPathComponent) - \(entry.url.deletingLastPathComponent().lastPathComponent)") {
                Task { await model.openRecentFolder(entry, undoManager: undoManager) }
            }
            .help(entry.url.path)
            .disabled(!model.canOpenRecentFolder(entry))
        }
        if model.sidebarFolders.history.entries.isEmpty {
            Text("No recent folders yet. Folders you open appear here.")
        }
        Divider()
        Button("Choose Folder…", action: model.requestOpenFolder).disabled(!model.canOpenFolders)
        // No retention policy exists for this device-local list. Clearing never closes projects.
        if !model.sidebarFolders.history.entries.isEmpty {
            Button("Clear Menu", action: model.clearRecentFolders)
        }
    }
}

#if DEBUG
#Preview("Recent folders - File menu contents") {
    DSPreviewPair { SidebarFolderRecentMenu(model: AppModel.preview(.empty), undoManager: nil) }
}
#endif
