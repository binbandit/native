import SwiftUI

/// An agent's icon on a tile, for large surfaces like Home's cards. App icons and glyphs share the
/// same frame and outline, so a row of agents reads as one set and a white app icon doesn't vanish
/// into a light card.
struct AgentIconTile: View {
    let agent: AgentDefinition
    var size: CGFloat = DS.Size.controlMD

    @Environment(\.agentIconStore) private var injectedStore

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        let isPicture = (injectedStore ?? .shared).artwork(for: agent, style: .tile).isPicture
        // App icons carry their own margin; glyphs sit at an SF Symbol's weight in the tile.
        AgentIcon(agent: agent, style: .tile, size: size * (isPicture ? 0.8 : 0.5))
            .frame(width: size, height: size)
            .background(.dsSurface, in: shape)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Agent icon tiles") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            ForEach(AgentIconPreviewFixtures.agents, id: \.id) { agent in
                AgentIconTile(agent: agent)
            }
        }
    }
    .agentIconPreviewStore()
}
#endif
