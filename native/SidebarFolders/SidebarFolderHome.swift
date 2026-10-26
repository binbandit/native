import SwiftUI

/// The folder has a home before it has a task. First launch offers an action, never an inert field.
struct SidebarFolderHome: View {
    let agents: [HomeAgent<AgentDefinition.ID>]
    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        let project = model.currentProject
        let isOpening = project.map { model.sidebarFolders.opening.contains($0.folderName) } == true
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(project?.name ?? "Choose a folder")
                    .font(DS.SidebarFolders.titleFont).tracking(DS.SidebarFolders.titleTracking)
                    .foregroundStyle(.dsTextPrimary)
                    .padding(.bottom, DS.Space.xl)
                Text(
                    project == nil
                        ? "Open the project you want to work in."
                        : isOpening ? "Opening your folder." : "What would you like to work on?"
                )
                .font(DS.SidebarFolders.ledeFont).foregroundStyle(.dsTextSecondary)
                if project == nil {
                    Button(action: model.requestOpenFolder) {
                        HStack(spacing: DS.Space.md) {
                            Text("Open Folder…")
                            if let key = CommandRegistry.shared.keyboardShortcut(for: .projectOpen) { Kbd(key) }
                        }
                    }
                    .buttonStyle(.ds(.primary))
                    .disabled(!model.canOpenFolders)
                    .padding(.top, DS.Space.xxl)
                }
                Text(
                    project == nil
                        ? "You can also drop a folder onto the sidebar."
                        : "Start a task below, or return to any task in the sidebar."
                )
                .font(.dsBody).foregroundStyle(.dsTextTertiary)
                .padding(.top, DS.Space.lg)
                if project == nil {
                    HomeNextAgentReadiness(agents: agents) { settings.open(.agents) }
                        .padding(.top, DS.Space.xxxl)
                }
            }
            .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
            .padding(.horizontal, DS.Space.xxl)
            .padding(.top, DS.SidebarFolders.emptyTop)
            .padding(.bottom, DS.Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            if project != nil {
                HomeNextStartField(maximumWidth: DS.ComposerSettings.width) { task in model.openHomeNextTask(task.id) }
                    .onAppear { model.homeNext.startFieldFocusRequests &+= 1 }
            }
        }
        .onAppear { model.setHomeNextVisible(true) }
        .onDisappear { model.setHomeNextVisible(false) }
        .background(.dsBackground)
        .dsToolbarBand(showsDivider: true)
        #if os(macOS)
        .toolbar(removing: .title)
        #endif
    }
}

#if DEBUG
#Preview("Folder home - First folder") {
    DSPreviewPair { SidebarFolderHome(agents: []).frame(width: 1000, height: 800) }
        .sidebarPreviewEnvironment(AppModel.preview(.empty))
}
#Preview("Folder home - No tasks") {
    let app = AppModel.preview(.empty)
    let project = app.projects.add(URL(filePath: "/Development/atlas"))
    app.focusProject(project.id)
    return DSPreviewPair { SidebarFolderHome(agents: []).frame(width: 1000, height: 800) }.sidebarPreviewEnvironment(
        app)
}
#endif
