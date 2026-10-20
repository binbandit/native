import SwiftUI

/// Agents Native knows about but can't find on this Mac, each with how to install it: Settings ▸
/// Agents and the new-session menu's Add Agent both show this. Native never runs the commands; once
/// the user has, Check Again looks again without a relaunch and says what it found.
struct AddAgentList: View {
    /// The agents to offer: enabled agents that aren't installed.
    let agents: [AgentDefinition]
    /// Each plugin's description, by plugin id, to say what an agent is.
    var summaries: [String: String] = [:]
    /// Reads the shell environment again, re-checks every agent, starts the ones now installed and
    /// returns them.
    let checkAgain: () async -> [AgentDefinition]

    @State private var isChecking = false
    @State private var outcome: String?

    var body: some View {
        if agents.isEmpty {
            EmptyStateView(
                "Every agent is installed",
                systemImage: "checkmark.circle",
                message: outcome ?? "Native found every agent its plugins know about. Plugins can add more."
            ) {
                checkAgainButton
                    .buttonStyle(.ds(.secondary))
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                    if index > 0 {
                        SeparatorLine()
                    }
                    AgentSetupCard(agent: agent, summary: summaries[agent.pluginID])
                }
                HStack(spacing: DS.Space.md) {
                    checkAgainButton
                        .buttonStyle(.ds(.secondary))
                    if isChecking {
                        DotGridLoader(pattern: .waiting)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    Text(outcome ?? "Installed one? Native checks your login shell's PATH.")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
        }
    }

    private var checkAgainButton: some View {
        Button(isChecking ? "Checking…" : "Check Again") {
            Task { await check() }
        }
        .disabled(isChecking)
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        let found = await checkAgain()
        outcome =
            found.isEmpty
            ? "Nothing new on your PATH. Open a new terminal to check the install worked."
            : "Added \(found.map(\.displayName).formatted(.list(type: .and)))."
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Add agent list") {
    DSPreviewPair {
        AddAgentList(agents: Array(AgentIconPreviewFixtures.agents.suffix(3)), checkAgain: { [] })
            .frame(width: 560)
    }
    .agentIconPreviewStore()
}

#Preview("Add agent list - Everything installed") {
    DSPreviewPair {
        AddAgentList(agents: [], checkAgain: { [] })
            .frame(width: 560, height: 280)
    }
}
#endif
