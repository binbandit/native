import SwiftUI

struct NewTasksWorkspaceRow: View {
    var project: Project?
    @Environment(\.settingsPlainly) private var plainly
    @Environment(GitSettings.self) private var settings
    @Environment(\.undoManager) private var undoManager
    @State private var showsSource = false

    private var local: GitSettings.NewTaskWorkspace? {
        project.flatMap { settings.overrides(forProjectAt: $0.url).newTaskWorkspace }
    }
    private func title(_ value: GitSettings.NewTaskWorkspace) -> String {
        value == .worktree ? "Its own worktree" : "The project folder"
    }
    private var receipt: NewTasksSettingReceipt {
        NewTasksSettingReceipt(
            title: "Work in", context: project.map { "in \($0.name)" } ?? "for all projects",
            value: title(local ?? settings.newTaskWorkspace),
            source: local != nil
                ? .project(project?.name ?? "Project") : settings.newTaskWorkspace == .worktree ? .native : .user,
            layers: [
                .init(name: project?.name ?? "Project", symbol: "folder", value: local.map(title), wins: local != nil),
                .init(
                    name: "You", symbol: "person",
                    value: settings.newTaskWorkspace == .worktree ? nil : title(settings.newTaskWorkspace),
                    wins: local == nil && settings.newTaskWorkspace != .worktree),
                .init(
                    name: "Native", symbol: "app", value: "Its own worktree",
                    wins: local == nil && settings.newTaskWorkspace == .worktree),
            ], note: "A project's choice comes first, then your setting for every project.")
    }

    var body: some View {
        if plainly { attributedRow } else { legacyRow }
    }

    private var legacyRow: some View {
        @Bindable var settings = settings
        return SettingsRow(
            id: GitSettingsPage.workspaceRow, "New tasks get",
            description: Text(
                "A worktree keeps parallel tasks from editing the same files. Worktrees live in ~/.native/worktrees.")
        ) {
            SettingsSelect(
                label: "New tasks get", selection: $settings.newTaskWorkspace,
                options: GitSettings.NewTaskWorkspace.allCases.map { .init(value: $0, title: $0.title) },
                isDefault: settings.newTaskWorkspace == .worktree)
        }
    }

    private var attributedRow: some View {
        SettingsRow(id: GitSettingsPage.workspaceRow, "Work in") {
            NewTasksSourceControl(receipt: receipt, showsSource: $showsSource) {
                NewTasksValueMenu(
                    label: "Work in",
                    selection: Binding<GitSettings.NewTaskWorkspace?>(
                        get: { project == nil ? settings.newTaskWorkspace : local },
                        set: { settings.setStartingWorkspace($0, project: project?.url, undoManager: undoManager) }),
                    options: (project == nil
                        ? [] : [.init(value: nil, title: "Default (\(title(settings.newTaskWorkspace)))")])
                        + GitSettings.NewTaskWorkspace.allCases.map { .init(value: $0, title: title($0)) },
                    isDefault: project == nil ? settings.newTaskWorkspace == .worktree : local == nil
                )
            }
            .contextMenu {
                Button("Why This Value…") { showsSource = true }
                Button("Reset") {
                    settings.setStartingWorkspace(nil, project: project?.url, undoManager: undoManager)
                }
            }
        }
    }
}

#if DEBUG
#Preview("New Tasks - Workspace") {
    DSPreviewPair {
        SettingsRowGroup { NewTasksWorkspaceRow() }.settingsPreviewPage()
    }.environment(GitSettings(defaults: PreviewUserDefaults())).environment(\.settingsPlainly, true)
}
#endif
