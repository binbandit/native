import SwiftUI

/// Add Agent, from the new-session menu: `AddAgentList` in a sheet, with a Done button.
struct AddAgentSheet: View {
    let agents: [AgentDefinition]
    var summaries: [String: String] = [:]
    let checkAgain: () async -> [AgentDefinition]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Add an Agent")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                Text("Install one in your terminal, then check again. Native never runs these commands.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
            .padding(DS.Space.xl)
            SeparatorLine()
            ScrollView {
                AddAgentList(agents: agents, summaries: summaries, checkAgain: checkAgain)
                    .padding(DS.Space.xl)
            }
            SeparatorLine()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Space.lg)
        }
        .frame(width: 520, height: 520)
        .background(.dsBackground)
    }
}

extension PluginRegistry {
    /// Each plugin's description, by plugin id: what Add Agent says an agent is.
    var descriptions: [String: String] {
        Dictionary(plugins.compactMap { loaded in loaded.plugin.manifest.description.map { (loaded.id, $0) } }) { $1 }
    }
}
