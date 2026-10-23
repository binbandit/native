import SwiftUI

struct NewTasksWorkspaceRow: View {
    @Environment(GitSettings.self) private var settings
    @Environment(\.settingsPlainly) private var plainly

    var body: some View {
        @Bindable var settings = settings
        SettingsRow(
            id: GitSettingsPage.workspaceRow, "New tasks get", plainly: .workspace,
            description: Text(
                "A worktree keeps parallel tasks from editing the same files. Worktrees live in ~/.native/worktrees."
            )
        ) {
            SettingsSelect(
                label: "New tasks get", selection: $settings.newTaskWorkspace,
                options: GitSettings.NewTaskWorkspace.allCases.map {
                    .init(value: $0, title: plainly && $0 != .worktree ? "The project folder" : $0.title)
                }, width: plainly ? DS.Settings.wideControl : SettingsMetrics.selectWidth,
                isDefault: settings.newTaskWorkspace == .worktree)
        }

    }
}

#if DEBUG
#Preview("New Tasks - Workspace") {
    DSPreviewPair {
        SettingsRowGroup { NewTasksWorkspaceRow() }.settingsPreviewPage()
    }
    .environment(GitSettings(defaults: PreviewUserDefaults()))
    .environment(\.settingsPlainly, true)
}
#endif
