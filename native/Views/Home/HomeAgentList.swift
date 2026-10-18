import SwiftUI

/// The agents Native will run, as a quiet line of glyphs and names. Agents that can't take tasks
/// yet are dimmed, so a missing install shows before the first task fails.
struct HomeAgentList<ID: Hashable>: View {
    let agents: [HomeAgent<ID>]

    var body: some View {
        HStack(spacing: DS.Space.xl) {
            ForEach(agents) { agent in
                HStack(spacing: DS.Space.sm) {
                    if let definition = agent.agent {
                        AgentIcon(agent: definition)
                    } else {
                        Image(systemName: agent.symbolName)
                            .font(.system(size: DS.Size.navIcon))
                    }
                    Text(agent.name)
                        .font(.dsBody)
                        .tracking(DS.Tracking.tight)
                }
                .foregroundStyle(agent.availability == .available ? .dsTextSecondary : .dsTextQuaternary)
                .help(help(for: agent))
            }
        }
        .lineLimit(1)
        .frame(height: DS.Size.controlSM)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agents")
    }

    private func help(for agent: HomeAgent<ID>) -> String {
        switch agent.availability {
        case .available, .creatingTask: "\(agent.name) is ready"
        case .starting: "\(agent.name) is starting"
        case .unavailable(let reason): "\(agent.name): \(reason)"
        }
    }
}
