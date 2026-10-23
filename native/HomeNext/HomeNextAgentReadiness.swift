import SwiftUI

struct HomeNextAgentReadiness: View {
    let agents: [HomeAgent<AgentDefinition.ID>]
    let manage: () -> Void

    var body: some View {
        let ready = agents.filter { $0.availability == .available }.map(\.name)
        let unavailable = agents.filter { $0.availability != .available }
        FlowLayout(spacing: DS.Space.md) {
            if !ready.isEmpty {
                Text("\(ready.formatted(.list(type: .and))) \(ready.count == 1 ? "is" : "are") ready.")
            }
            ForEach(unavailable) { agent in
                Button("\(agent.name): \(reason(agent))", action: manage)
                    .buttonStyle(.plain).underline().foregroundStyle(.dsTextPrimary).dsHitTarget(DS.Size.controlXS)
            }
            if agents.isEmpty {
                Button("Set up an agent", action: manage).buttonStyle(.plain).underline().dsHitTarget(DS.Size.controlXS)
            }
        }
        .font(.dsBody).foregroundStyle(.dsTextSecondary)
    }

    private func reason(_ agent: HomeAgent<AgentDefinition.ID>) -> String {
        switch agent.availability {
        case .available: "ready"
        case .starting, .creatingTask: "starting"
        case .unavailable(let reason): reason
        }
    }
}

#if DEBUG
#Preview("Next agents - Ready and unavailable") { HomeNextPreviewFixtures.page(.first) }
#endif
