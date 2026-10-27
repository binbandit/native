import ACP
import SwiftUI

/// How full a session's context window is, as a ring; a click opens the breakdown. `.ring` fits a
/// sidebar task row; `.labeled` adds the percentage, for the composer's controls; `.field` is that at
/// Fine print's 24pt, among the field's trailing controls.
struct ContextIndicator<Source: ContextSource>: View {
    enum Style {
        case ring
        case labeled
        case field
    }

    let source: Source
    var style: Style = .ring
    /// Where the breakdown opens: above the composer, beside a sidebar row.
    var arrowEdge: Edge = .top
    /// How full the window must be before the indicator shows (Fine print's field: from 70%); its
    /// breakdown still opens from View ▸ Show Context Use below that.
    var revealsAt: Double = 0
    /// Whether the breakdown is open, when something else opens it too (View ▸ Show Context Use).
    var breakdown: Binding<Bool>?

    @State private var ownBreakdown = false
    @State private var isHovered = false

    private var isShowingBreakdown: Bool {
        get { breakdown?.wrappedValue ?? ownBreakdown }
        nonmutating set {
            if let breakdown { breakdown.wrappedValue = newValue } else { ownBreakdown = newValue }
        }
    }

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
            .popover(isPresented: breakdown ?? $ownBreakdown, arrowEdge: arrowEdge) {
                ContextBreakdownView(source: source)
                    .dsPopoverBackground()
            }
        }
    }

    /// A row only shows a ring once there's something to show; the composer keeps its place for
    /// agents that can explain their context even before the first usage update.
    private var isVisible: Bool {
        let available = source.fractionUsed != nil || (style != .ring && source.reportStatus != .unsupported)
        return available && (isShowingBreakdown || (source.fractionUsed ?? 0) >= revealsAt)
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
        case .labeled, .field:
            let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            HStack(spacing: DS.Space.sm) {
                ring
                Text(source.fractionUsed.map(DSFormat.percent) ?? "Context")
                    .monospacedDigit()
                    .contentTransition(.numericText(value: source.fractionUsed ?? 0))
            }
            .font(style == .field ? .dsMonoCaption : .dsBody)
            .foregroundStyle(isHovered || isShowingBreakdown ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.sm)
            .frame(height: style == .field ? DS.ComposerSettings.controlHeight : DS.Size.composerPill)
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

extension FocusedValues {
    /// The focused task's context breakdown, for View ▸ Show Context Use.
    @Entry var contextUsePopover: Binding<Bool>?
}

#if NATIVE_PREVIEWS_WIP
#Preview("Context indicator") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.md) {
            ForEach([240_000, 820_000, 960_000], id: \.self) { used in
                HStack {
                    ContextIndicator(source: PreviewContextSource.claude(used: used))
                    ContextIndicator(source: PreviewContextSource.claude(used: used), style: .labeled)
                }
            }
            HStack {
                ContextIndicator(source: PreviewContextSource.codex)
                ContextIndicator(source: PreviewContextSource.codex, style: .labeled)
            }
        }
    }
}
#endif
