import ACP
import NativePolicy
import SwiftUI

/// One default for every provider, with an optional project override.
struct PermissionDefaultsRow: View {
    var project: Project.ID?
    @AppStorage private var stored: String?
    @AppStorage(TaskPermissionDefaults.key) private var global: String = TaskPermissionMode.fullAccess.rawValue
    @Environment(PolicyCenter.self) private var policy: PolicyCenter?

    init(project: Project.ID? = nil) {
        self.project = project
        TaskPermissionDefaults.migrate(in: .standard)
        _stored = AppStorage(TaskPermissionDefaults.key(project: project?.uuidString))
    }

    private var selected: TaskPermissionMode {
        TaskPermissionMode(rawValue: stored ?? global) ?? .fullAccess
    }

    private var effective: TaskPermissionMode? {
        TaskPermissionMode.allCases.reversed().first { $0.rank <= selected.rank && !isForbidden($0) }
    }

    private var explanation: String {
        guard let effective else {
            return "Your organization does not allow any permission mode. Contact your administrator."
        }
        return effective.summary + (effective == selected ? "" : " Your organization restricts the saved choice.")
    }

    var body: some View {
        SettingsRow(
            id: SettingsRowID("permissions.default\(project.map { ".\($0.uuidString)" } ?? "")"),
            "Permissions", description: Text(explanation)
        ) {
            NewTasksValueMenu(
                label: "Default permissions",
                value: effective.map { project != nil && stored == nil ? "Default (\($0.title))" : $0.title }
                    ?? "No allowed mode",
                isDefault: project != nil && stored == nil
            ) {
                if project != nil {
                    Button("Follow all tasks") { stored = nil }
                    Divider()
                }
                ForEach(TaskPermissionMode.allCases, id: \.self) { mode in
                    Button {
                        stored = mode.rawValue
                    } label: {
                        Text(mode.title)
                        Text(mode.summary)
                        if mode == selected { Image(systemName: "checkmark") }
                    }
                    .disabled(isForbidden(mode))
                }
            }
            .help("Applies to new tasks with every agent. Your organization's policy takes precedence.")
        }
    }

    private func isForbidden(_ mode: TaskPermissionMode) -> Bool {
        let forbidden = (policy ?? PolicyCenter.shared).policy.forbiddenPermissionModes
        return forbidden.contains(mode.rawValue) || forbidden.contains { TaskPermissionMode.migrating($0) == mode }
    }
}

#if DEBUG
#Preview("Permission defaults") {
    DSPreviewPair {
        SettingsRowGroup { PermissionDefaultsRow() }.settingsPreviewPage()
    }
    .defaultAppStorage(PreviewUserDefaults())
}
#endif
