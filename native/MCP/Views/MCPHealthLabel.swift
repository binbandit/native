import SwiftUI

/// A server's status as a dot and a few words: the one way MCP views show it.
struct MCPHealthLabel: View {
    let health: MCPHealth

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if health == .checking {
                DotGridLoader(pattern: .waiting)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            } else {
                StatusDot(color: health.color)
            }
            Text(health.label)
                .font(.dsCaption)
                .foregroundStyle(health.needsAttention ? health.color : .dsTextSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(health.label)")
    }
}

/// Context tokens a server's tools take, as Claude Code's `/context` counts them.
struct MCPContextCostLabel: View {
    let cost: MCPContextCost

    var body: some View {
        Text("\(TokenFormat.compact(cost.tokens)) tokens of context · \(TokenFormat.share(cost.tokens, of: cost.window))")
            .font(.dsCaption)
            .foregroundStyle(cost.fraction >= 0.1 ? .dsWarning : .dsTextSecondary)
            .help("What this server's tool definitions take in every Claude Code session, from its latest /context report (\(cost.capturedAt.formatted(.relative(presentation: .named)))).")
    }
}
