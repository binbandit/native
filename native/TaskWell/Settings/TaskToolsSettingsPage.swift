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
            SessionToolRegistry.shared.wellTools.map { tool in
                SettingsSearchEntry(
                    id: TaskToolsSettingsPage.rowID(tool), title: tool.title, description: tool.summary,
                    keywords: ["task tools", "well"] + [tool.pluginName].compactMap { $0 })
            }
        },
        content: { TaskToolsSettingsPage() }
    )
}

/// One row per tool, in key order, then plugins' tools: a switch for a tool with one place, a
/// pop-up for one that can open beside the conversation or over it. Off means it never reaches
/// the well.
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
                ForEach(registry.wellTools) { tool in
                    row(tool)
                }
            }
        }
    }

    private func row(_ tool: TaskWellTool) -> some View {
        let places = tool.spec.places.filter { $0 != .off }
        return SettingsRow(
            id: Self.rowID(tool), title: Text(tool.title),
            description: tool.summary.isEmpty ? nil : Text(tool.summary), detail: detail(tool).map { Text($0) }
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
                        // Its one place, even for a plugin's tool that starts off.
                        set: { registry.setPlace($0 ? places.first ?? .off : .off, for: tool.spec) }))
            }
        }
    }

    /// Who added a plugin's tool, and why the pull request gives way to Export Patch.
    private func detail(_ tool: TaskWellTool) -> String? {
        if let plugin = tool.pluginName { return "Added by the \(plugin) plugin." }
        return tool == .pullRequest ? gitHubManagement ?? managedGitHub : nil
    }

    private func place(of tool: TaskWellTool) -> Binding<SessionToolPlace> {
        Binding(get: { registry.place(for: tool.spec) }, set: { registry.setPlace($0, for: tool.spec) })
    }

    /// Air-gapped and internal-only installs, or a network policy that turns GitHub off.
    private var managedGitHub: String? {
        guard let policy, policy.isNetworkManaged, policy.isGitHubOutOfReach
        else { return nil }
        return "This install has no route to GitHub, so the well offers Export Patch instead. \(policy.managementLine)."
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
#Preview("Task Tools - Defaults, managed GitHub and a plugin's tool") {
    DSPreviewPair {
        VStack(spacing: 0) {
            TaskToolsSettingsPage(registry: SessionToolRegistry(defaults: PreviewUserDefaults()))
            TaskToolsSettingsPage(
                registry: SessionToolRegistry(defaults: PreviewUserDefaults()),
                gitHubManagement:
                    "This install has no route to GitHub, so the well offers Export Patch instead. Managed by Northwind Federal IT · #it-help."
            )
            TaskToolsSettingsPage(registry: TaskWellPreviewFixtures.registryWithPluginTool())
        }
        .settingsPreviewPage()
    }
    .environment(CommandRegistry.shared)
}
#endif
