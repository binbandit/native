import SwiftUI

/// Adding a folder belongs to Projects, with the same control as the folders' task headers.
struct SidebarProjectsHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SidebarSectionLabel("Projects") {
            IconButton("Open Folder…", systemImage: "plus", size: .small, action: model.requestOpenFolder)
                .focusable()
                .disabled(!model.canOpenFolders || !model.sidebarFolders.opening.isEmpty)
                .help("Open Folder… (⌘O)")
                .accessibilityHint("Choose a folder to add to Native")
        }
        .frame(minHeight: DS.Size.minimumHitTarget)
    }
}

#if DEBUG
#Preview("Projects header - Rest") {
    DSPreviewPair { SidebarProjectsHeader().frame(width: DS.Size.sidebarWidth) }
        .sidebarPreviewEnvironment(SidebarFolderPreviewFixtures.model("F1"))
}
#Preview("Projects header - No projects") {
    DSPreviewPair { SidebarProjectsHeader().frame(width: DS.Size.sidebarWidth) }
        .sidebarPreviewEnvironment(SidebarFolderPreviewFixtures.model("F5"))
}
#Preview("Projects header - Managed restriction") {
    DSPreviewPair { SidebarProjectsHeader().frame(width: DS.Size.sidebarWidth) }
        .sidebarPreviewEnvironment(SidebarFolderPreviewFixtures.model("blocked"))
}
#Preview("Projects header - Opening") {
    DSPreviewPair { SidebarProjectsHeader().frame(width: DS.Size.sidebarWidth) }
        .sidebarPreviewEnvironment(SidebarFolderPreviewFixtures.model("F10"))
}
#endif
