import SessionTools
import SwiftUI

/// Settings ▸ Session Tools: a row per tool saying what it shows, with where it lives (under the
/// title, beside the conversation, under the composer) or Off. A change shows on every task at once.
struct SessionToolsSettingsPage: View {
    let registry: SessionToolRegistry
    @Experiment(.sessionTools) private var usesSessionTools

    static func row(for tool: SessionToolID) -> SettingsRowID {
        SettingsRowID("sessionTools.\(tool.rawValue)")
    }

    /// Wide enough for "Beside the Conversation".
    private static let selectWidth: CGFloat = 200

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Session Tools",
                description: Text(
                    "A task is the conversation and the composer. Each tool shows up only when it has something to "
                        + "show, in the place you choose. With every tool off, that's all there is."))
            if !usesSessionTools {
                SettingsNote("Session Tools is in Labs", systemImage: "flask") {
                    Text("Turn it on in Labs to see these places on the session screen.")
                }
            }
            SettingsRowGroup {
                ForEach(registry.tools) { tool in
                    SettingsRow(
                        id: Self.row(for: tool.id), tool.title, icon: tool.systemImage,
                        description: Text(Self.summary(tool.id))
                    ) {
                        SettingsSelect(
                            label: tool.title,
                            selection: Binding(
                                get: { registry.place(of: tool.id) }, set: { registry.move(tool.id, to: $0) }),
                            options: tool.spec.places.map { .init(value: $0, title: $0.settingsTitle) },
                            width: Self.selectWidth)
                    }
                }
            }
            if !registry.arrangement.isDefault {
                SettingsRowGroup {
                    SettingsRow("Where each tool starts", description: Text("Put every tool back in its own place.")) {
                        Button("Reset") { registry.resetArrangement() }
                            .buttonStyle(.settings)
                    }
                }
            }
        }
    }

    /// What each of Native's tools shows, for its row.
    private static func summary(_ tool: SessionToolID) -> String {
        switch tool {
        case .changes: "What the agent changed, to review and commit. Shows while there are uncommitted changes."
        case .run: "Which of the project's actions is running, or failed. Opens its output."
        case .terminal: "Shells in the task's folder, and every action's run, each a tab."
        case .subagents: "The agents it handed work to, and their conversations. Shows while there are any."
        case .pullRequest: "The branch's pull request. Shows once there is one."
        case .openIn: "The task's folder in your editor, one click away."
        default: "Added by a plugin."
        }
    }
}

extension SessionToolPlace {
    /// How Settings names the place.
    var settingsTitle: String {
        switch self {
        case .fact: "Under the Title"
        case .side: "Beside the Conversation"
        case .workbench: "Under the Composer"
        case .off: "Off"
        }
    }
}
