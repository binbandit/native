import SwiftUI

/// One agent the user could add: what it is, the command that installs it, how it signs in, and
/// a link to its docs.
struct AgentSetupCard: View {
    let agent: AgentDefinition
    /// The plugin's description of the agent.
    var summary: String?

    private var setup: AgentSetupGuide? {
        agent.manifest.setup
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            AgentIcon(agent: agent, size: DS.Size.controlXS)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                    Text(agent.displayName)
                        .font(.dsCalloutMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Spacer(minLength: DS.Space.md)
                    if let docs = setup?.docs {
                        Link(destination: docs) {
                            Label("Docs", systemImage: "arrow.up.right")
                                .labelStyle(AgentSetupTrailingIconLabelStyle())
                        }
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .help(docs.absoluteString)
                    }
                }
                if let summary {
                    Text(summary)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let install = setup?.install {
                    AgentSetupCommand(command: install)
                        .padding(.top, DS.Space.xxs)
                } else {
                    Text("Install `\(agent.manifest.command)` so it's on your PATH, then check again.")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
                if let signIn = setup?.signIn {
                    Text("Then sign in with `\(signIn)`, or from Native when it asks.")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Docs ↗": the arrow after the title, the way links out of the app read.
private struct AgentSetupTrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Space.xxs) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
