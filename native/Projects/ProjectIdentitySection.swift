import SwiftUI

/// A project's name, folder and icon: how it shows across Native.
struct ProjectIdentitySection: View {
    let project: Project

    @Environment(AppModel.self) private var model
    @Environment(\.projectIconStore) private var injectedIconStore
    @State private var isPickingIcon = false

    /// The icon's preview on its row.
    private static let previewSide = DS.Size.controlSM

    private var rows: ProjectSettingsRows { ProjectSettingsRows(project: project.id) }
    private var iconStore: ProjectIconStore { injectedIconStore ?? .shared }

    var body: some View {
        SettingsRowGroup {
            SettingsRow(
                id: rows.name, "Name",
                description: Text(
                    "Shown throughout Native. Clear it to use the folder name; the folder on disk keeps its name.")
            ) {
                HStack(spacing: DS.Space.lg) {
                    SettingsValue(project.baseName)
                    Button("Rename…") { model.requestRenameProject(project.id) }
                }
            }
            folderRow
            SettingsRow(id: rows.icon, "Icon", description: Text(iconDescription)) {
                HStack(spacing: DS.Space.lg) {
                    ProjectAvatar(
                        name: project.name, icon: iconStore.icon(for: project, size: Self.previewSide),
                        size: Self.previewSide)
                    Button("Change Icon…") { isPickingIcon = true }
                        .popover(isPresented: $isPickingIcon, arrowEdge: .bottom) {
                            ProjectIconPicker(project: project, store: iconStore)
                                .dsPopoverBackground()
                        }
                }
            }
        }
        .task(id: project.id) { await iconStore.resolve(project) }
    }

    @ViewBuilder
    private var folderRow: some View {
        if let missing = model.missingFolder(of: project.id) {
            SettingsRow(
                id: rows.folder, "Folder",
                description: Text("Native can't find \(project.url.abbreviatedPath). Move it back, then look again.")
            ) {
                Button("Look Again") { Task { await model.retry(missing) } }
            }
        } else {
            SettingsRow(
                id: rows.folder, "Folder",
                description: Text(verbatim: project.url.abbreviatedPath).font(SettingsTextStyle.mono.font)
            ) {
                if PlatformFileBrowser.canReveal, project.host == .local {
                    Button("Show in Finder") { PlatformFileBrowser.reveal(project.url) }
                } else {
                    Button("Copy Path") { DSPasteboard.copy(project.path) }
                }
            }
        }
    }

    private var iconDescription: String {
        switch iconStore.choice(for: project.id) {
        case .automatic:
            if let path = iconStore.detectedPath(for: project.id) {
                "Found in the project, from \(path)."
            } else {
                "Native found no icon in the project, so it shows the initial. Pick an emoji, a symbol or an image."
            }
        case .file(let path): "\(path), from the project. It follows changes to the file."
        case .initial: "The project's initial."
        case .emoji: "An emoji you picked."
        case .symbol: "A symbol you picked."
        case .image: "An image you picked. Native keeps a copy, so the original can move."
        }
    }
}

#if DEBUG
#Preview("Project identity - Folder name") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let project = app.previewProject() {
            ProjectIdentitySection(project: project)
                .settingsPreviewPage()
        }
    }
    .sidebarPreviewEnvironment(app)
}
#endif

#if DEBUG
#Preview("Project identity - Custom name") {
    let app = AppModel.preview()
    if let project = app.previewProject() {
        app.renameProject(project.id, to: "Native at Work")
    }
    return DSPreviewPair {
        if let project = app.previewProject() {
            ProjectIdentitySection(project: project)
                .settingsPreviewPage()
        }
    }
    .sidebarPreviewEnvironment(app)
}
#endif
