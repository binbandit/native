import SwiftUI

/// The first task begins with its message. Opening a folder remains a separate, optional action.
struct NoProjectHome: View {
    let agents: [HomeAgent<AgentDefinition.ID>]
    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                Text("What would you like to do?")
                    .font(DS.HomeNext.titleFont).tracking(DS.HomeNext.titleTracking)
                    .foregroundStyle(.dsTextPrimary)
                Text("Ask a question, draft something, or explore an idea.")
                    .font(DS.SidebarFolders.ledeFont).foregroundStyle(.dsTextSecondary)
                HomeNextStartField(maximumWidth: DS.ComposeTask.width) { task in model.openHomeNextTask(task.id) }
                    .padding(.horizontal, -DS.Space.xxl)
                    .padding(.bottom, -DS.Space.xl)
                Text("Private task files. You can move this task to a project later.")
                    .font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if !agents.contains(where: { $0.availability == .available }) {
                    HomeNextAgentReadiness(agents: agents) { settings.open(.agents) }
                }
                if !model.offersSidebarFolders {
                    Button("Open Folder…", action: model.requestOpenFolder)
                        .buttonStyle(.ds(.ghost)).disabled(!model.canOpenFolders)
                }
            }
            .frame(maxWidth: DS.ComposeTask.width, alignment: .leading)
            .padding(.horizontal, DS.Space.xxl)
            .padding(.top, DS.SidebarFolders.emptyTop)
            .padding(.bottom, DS.Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.dsBackground)
        .dsToolbarBand(showsDivider: false)
        .onAppear { model.setHomeNextVisible(true) }
        .onDisappear { model.setHomeNextVisible(false) }
    }
}

#if DEBUG
#Preview("Home - No project, agent setup") {
    DSPreviewPair { NoProjectHome(agents: []).frame(width: 1100, height: 850) }
        .sidebarPreviewEnvironment(AppModel.preview(.empty))
}
#endif
