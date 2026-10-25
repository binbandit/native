import NativeCommands
import SessionTools
import SwiftUI

extension SettingsPane.ID {
    static let taskTools = Self("taskTools")
}

extension SettingsPane {
    /// Settings ▸ Task Tools: what the well opens and where. Listed while the well is on.
    static let taskTools = SettingsPane(
        id: .taskTools,
        title: "Task Tools",
        systemImage: "square.split.bottomrightquarter",
        group: .tasks,
        order: 35,
        keywords: ["well", "changes", "terminal", "dev", "subagents", "pull request", "placement", "workbench"],
        searchEntries: {
            TaskWellTool.allCases.map { tool in
                SettingsSearchEntry(
                    id: TaskToolsSettingsPage.rowID(tool), title: tool.title,
                    description: TaskToolsSettingsPage.summary(of: tool), keywords: ["task tools", "well"])
            }
        },
        content: { TaskToolsSettingsPage() }
    )
}

/// One row per tool, in key order: a switch for a tool with one place, a pop-up for Changes,
/// which can open beside the conversation or over it. Off means it never reaches the well.
struct TaskToolsSettingsPage: View {
    static func rowID(_ tool: TaskWellTool) -> SettingsRowID {
        SettingsRowID("taskTools.\(tool.spec.id.rawValue)")
    }

    var registry = SessionToolRegistry.shared
    /// Why GitHub is out of reach, when the organization keeps it there.
    var gitHubManagement: String?
    @Environment(PolicyCenter.self) private var policy: PolicyCenter?

    var body: some View {
        SettingsPage {
            SettingsHeader(
                title: "Task Tools",
                description: Text("What a task's well opens, and where. A tool that's off never shows in the well.")
            ) {
                Button("Restore Defaults", systemImage: "arrow.counterclockwise", action: registry.resetArrangement)
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .disabled(registry.arrangement.isDefault)
                    .help("Put every tool back where it starts")
            }
            SettingsRowGroup {
                ForEach(TaskWellTool.allCases) { tool in
                    row(tool)
                }
            }
        }
    }

    private func row(_ tool: TaskWellTool) -> some View {
        let places = tool.spec.places.filter { $0 != .off }
        return SettingsRow(
            id: Self.rowID(tool), title: Text(tool.title), description: Text(Self.summary(of: tool)),
            detail: tool == .pullRequest ? (gitHubManagement ?? managedGitHub).map { Text($0) } : nil
        ) {
            if let shortcut = CommandRegistry.shared.shortcut(for: tool.command) {
                Text(shortcut.displayString)
                    .font(DS.TaskWell.shortcut)
                    .foregroundStyle(.dsTextTertiary)
            }
        } control: {
            if places.count > 1 {
                SettingsSelect(
                    label: tool.title, selection: place(of: tool),
                    options: tool.spec.places.map { .init(value: $0, title: Self.title(of: $0)) },
                    width: DS.Settings.wideControl, isDefault: registry.place(for: tool.spec) == tool.spec.defaultPlace)
            } else {
                SettingsSwitch(
                    tool.title,
                    isOn: Binding(
                        get: { registry.place(for: tool.spec) != .off },
                        set: { registry.setPlace($0 ? tool.spec.defaultPlace : .off, for: tool.spec) }))
            }
        }
    }

    private func place(of tool: TaskWellTool) -> Binding<SessionToolPlace> {
        Binding(get: { registry.place(for: tool.spec) }, set: { registry.setPlace($0, for: tool.spec) })
    }

    /// Air-gapped and internal-only installs, or a network policy that turns GitHub off.
    private var managedGitHub: String? {
        guard let policy, policy.isNetworkManaged, policy.isGitHubOutOfReach
        else { return nil }
        return "\(policy.managementLine). This install has no route to GitHub, so the well offers Export Patch instead."
    }

    static func summary(of tool: TaskWellTool) -> String {
        switch tool {
        case .changes: "Review and commit what the task changed. In a narrow window it takes the conversation's place."
        case .terminal: "A shell in the task's folder, under the composer."
        case .dev: "Your project's actions, such as a dev server, under the composer."
        case .subagents: "The task's workers, beside the conversation."
        case .pullRequest: "The branch's pull request and its checks."
        }
    }

    private static func title(of place: SessionToolPlace) -> String {
        switch place {
        case .side: "Beside the conversation"
        case .fact: "Over the conversation"
        case .workbench: "Under the composer"
        case .off: "Off"
        }
    }
}

#if DEBUG
#Preview("Task Tools - Defaults and managed GitHub") {
    DSPreviewPair {
        VStack(spacing: 0) {
            TaskToolsSettingsPage(registry: SessionToolRegistry(defaults: PreviewUserDefaults()))
            TaskToolsSettingsPage(
                registry: SessionToolRegistry(defaults: PreviewUserDefaults()),
                gitHubManagement:
                    "Managed by Northwind Federal IT. This install has no route to GitHub, so the well offers Export Patch instead."
            )
        }
        .settingsPreviewPage()
    }
    .environment(CommandRegistry.shared)
}
#endif
