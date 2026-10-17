import ACP
import SwiftUI

/// How full a session's context window is, as a ring; a click opens the breakdown. `.ring` fits a
/// sidebar task row; `.labeled` adds the percentage, for the composer's controls.
struct ContextIndicator<Source: ContextSource>: View {
    enum Style {
        case ring
        case labeled
    }

    let source: Source
    var style: Style = .ring
    /// Where the breakdown opens: above the composer, beside a sidebar row.
    var arrowEdge: Edge = .top

    @State private var isShowingBreakdown = false
    @State private var isHovered = false

    var body: some View {
        if isVisible {
            Button {
                isShowingBreakdown.toggle()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .accessibilityLabel("Context")
            .accessibilityValue(source.fractionUsed.map { "\(DSFormat.percent($0)) full" } ?? "Not reported yet")
            .accessibilityHint("Shows what fills the context window")
            .popover(isPresented: $isShowingBreakdown, arrowEdge: arrowEdge) {
                ContextBreakdownView(source: source)
            }
        }
    }

    /// A row only shows a ring once there's something to show; the composer keeps its place for
    /// agents that can explain their context even before the first usage update.
    private var isVisible: Bool {
        source.fractionUsed != nil || (style == .labeled && source.reportStatus != .unsupported)
    }

    @ViewBuilder
    private var label: some View {
        // The ring's own tooltip would hide the fuller one on the button.
        let ring = ContextUsageRing(fraction: source.fractionUsed ?? 0, size: UsageMetrics.ringSize)
            .allowsHitTesting(false)
        switch style {
        case .ring:
            ring
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                .contentShape(.rect)
        case .labeled:
            let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            HStack(spacing: DS.Space.sm) {
                ring
                Text(source.fractionUsed.map(DSFormat.percent) ?? "Context")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: source.fractionUsed ?? 0))
            }
            .font(.dsBody)
            .foregroundStyle(isHovered || isShowingBreakdown ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.sm)
            .frame(height: DS.Size.composerPill)
            .background(isShowingBreakdown ? Color.dsSelected : isHovered ? .dsHover : .clear, in: shape)
            .contentShape(shape)
            .trackHover($isHovered)
            .animation(.dsStandard, value: source.fractionUsed)
        }
    }

    private var tooltip: String {
        guard let usage = source.usage, usage.size > 0 else {
            return "Context\nClick to see what fills it"
        }
        let cost = usage.cost.map { " · \($0.amount.formatted(.currency(code: $0.currency))) spent" } ?? ""
        return """
        Context \(DSFormat.percent(usage.fractionUsed)) full
        \(DSFormat.tokens(usage.used)) of \(DSFormat.tokens(usage.size)) tokens\(cost)
        Click for a breakdown
        """
    }
}
