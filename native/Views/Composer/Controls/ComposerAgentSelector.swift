import SwiftUI

/// A compact first section shared by both composers. Long plugin names wrap instead of shrinking.
struct ComposerAgentSelector: View {
    let agents: [ComposerAgentModel]
    let current: AgentDefinition.ID?
    var pending: AgentDefinition.ID?
    var isBusy = false
    var highlighted: AgentDefinition.ID?
    let onChoose: (AgentDefinition.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerSettingsHeader("Agent")
            FlowLayout(spacing: DS.Space.xs) {
                ForEach(agents, id: \.agent) { agent in
                    ComposerAgentSelectorButton(
                        agent: agent, isCurrent: agent.agent == current,
                        isPending: agent.agent == pending, isBusy: isBusy || pending != nil,
                        isHighlighted: agent.agent == highlighted
                    ) { onChoose(agent.agent) }
                }
            }
            .padding(.horizontal, DS.ComposerSettings.popoverInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch Agent")
    }
}

private struct ComposerAgentSelectorButton: View {
    let agent: ComposerAgentModel
    let isCurrent: Bool
    let isPending: Bool
    let isBusy: Bool
    let isHighlighted: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control)
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                if isCurrent || isPending || agent.isManaged {
                    ComposerSettingsGutter(mark: isPending ? .loading : agent.isManaged ? .lock : .check)
                }
                Text(agent.agentName).lineLimit(1)
            }
            .font(DS.ComposerSettings.rowFont)
            .foregroundStyle(agent.unavailable == nil ? .dsTextPrimary : .dsTextTertiary)
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: DS.ComposerSettings.rowHeight)
            .background(isHighlighted ? Color.dsSelected : isHovered ? .dsHover : .clear, in: shape)
            .overlay {
                if isHighlighted {
                    shape.strokeBorder(.dsKeyboardFocusIndicator, lineWidth: DS.ComposerSettings.focusLineWidth)
                }
            }
            .contentShape(shape)
            .dsFocusShape(shape)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .disabled(agent.unavailable != nil || isBusy)
        .accessibilityIdentifier("composer-agent-\(agent.agent.rawValue)")
        .accessibilityLabel("Switch to \(agent.agentName)")
        .accessibilityValue(isPending ? "Starting" : isCurrent ? "Current agent" : agent.unavailable ?? "")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .help(agent.unavailable ?? "Continue this task with \(agent.agentName). Undo is available before sending.")
    }
}

#if DEBUG
#Preview("Agent selector - Two and four agents, unavailable and preparing") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ComposerAgentSelector(
                agents: ComposerAgentSwitchFixtures.agents(count: 2), current: .init(rawValue: "claude-code")
            ) { _ in }
            ComposerAgentSelector(
                agents: ComposerAgentSwitchFixtures.agents(count: 4), current: .init(rawValue: "claude-code")
            ) { _ in }
            ComposerAgentSelector(
                agents: ComposerAgentSwitchFixtures.agents(count: 4), current: .init(rawValue: "claude-code"),
                pending: .init(rawValue: "codex")
            ) { _ in }
        }
        .frame(width: DS.ComposerSettings.popoverWidth)
    }
}
#endif
