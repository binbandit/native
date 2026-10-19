import ACP
import SwiftUI

/// A long run of tool work as one block, so a turn with a hundred calls takes the room of six: a
/// header that counts it ("37 tool calls · 2 running · 1 failed") with a glyph per kind, over a
/// short list that scrolls. While the run grows the list follows the newest call, unless the user
/// scrolled it back, as a terminal does. Its rows are the usual closed tool rows and open one by
/// one inside it; the header closes the whole list.
struct ToolRunView: View, Equatable {
    let run: TranscriptActivityRun
    let session: SessionModel

    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?
    @State private var isHovering = false
    /// Whether the list shows its end, so new calls should scroll into view.
    @State private var isFollowing = true
    @State private var position = ScrollPosition(edge: .bottom)

    /// A run changes only with its items; the session is always the same one.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.run == rhs.run
    }

    private var isOpen: Bool {
        disclosures?.isRunOpen(run.id) ?? true
    }

    var body: some View {
        let calls = run.calls
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Button {
                withAnimation(.reveal) { disclosures?.toggleRun(run.id) }
            } label: {
                ToolRunHeader(calls: calls, isOpen: isOpen, isHovering: isHovering)
            }
            .buttonStyle(.plain)
            .trackHover($isHovering)
            .accessibilityValue(isOpen ? "expanded" : "collapsed")
            .accessibilityHint(isOpen ? "Hides the tool calls" : "Shows the tool calls")

            if isOpen {
                list
                    .transition(RevealTransition())
            }
        }
    }

    private var list: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        return ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(run.items.indices, id: \.self) { index in
                    row(run.items[index], at: index)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: ToolRunScrollState.self) { [threshold = DS.Space.lg] geometry in
            ToolRunScrollState(
                contentHeight: geometry.contentSize.height,
                isAtEnd: geometry.visibleRect.maxY >= geometry.contentSize.height - threshold)
        } action: { old, new in
            // A new call moves the end away without the user doing anything; only their scrolling
            // decides whether the list follows.
            if new.contentHeight == old.contentHeight {
                isFollowing = new.isAtEnd
            }
        }
        .onChange(of: run.items.count) {
            if isFollowing { position.scrollTo(edge: .bottom) }
        }
        .frame(height: TranscriptMetrics.toolRunListHeight)
        .overlay { shape.strokeBorder(.dsSeparator) }
        .clipShape(shape)
    }

    @ViewBuilder private func row(_ item: TranscriptItem, at index: Int) -> some View {
        switch item {
        case .toolCall(let call):
            // Requests waiting on the user end a run, so none of these answers the permission keys.
            ToolCallView(call: call) { [session] option in
                Task { await session.choose(option, forToolCall: call.id) }
            }
            .equatable()
            .environment(\.permissionShortcutsEnabled, false)
        case .message(let message):
            MessageView(message: message, thinking: run.thinking[index])
                .equatable()
                .padding(.vertical, DS.Space.xs)
        case .notice, .subagent, .sessionMessage:
            // Runs hold only tool calls and reasoning.
            EmptyView()
        }
    }
}

private struct ToolRunScrollState: Equatable {
    var contentHeight: CGFloat
    var isAtEnd: Bool
}

/// "37 tool calls · 2 running · 1 failed", then a glyph and count per kind of work.
private struct ToolRunHeader: View {
    let calls: [ToolCallState]
    let isOpen: Bool
    let isHovering: Bool

    var body: some View {
        let running = calls.count { !$0.status.isFinished }
        let failed = calls.count { $0.status == .failed }
        HStack(spacing: DS.Space.sm) {
            DisclosureChevron(isExpanded: isOpen)
                .frame(width: DS.Size.rowLeading)
            Text(summary(running: running, failed: failed))
                .foregroundStyle(isHovering ? Color.dsTextPrimary : .dsTextSecondary)
                .monospacedDigit()
                .shimmering(running > 0)
                .layoutPriority(1)
            breakdown
            Spacer(minLength: 0)
        }
        .font(.dsBody)
        .lineLimit(1)
        .padding(.vertical, DS.Space.xs)
        .contentShape(.rect)
    }

    private func summary(running: Int, failed: Int) -> String {
        var parts = ["\(calls.count) tool calls"]
        if running > 0 { parts.append("\(running) running") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }

    private var breakdown: some View {
        let counts = Dictionary(grouping: calls, by: \.category.glyph).mapValues(\.count)
        return HStack(spacing: DS.Space.md) {
            ForEach(DSToolGlyph.allCases.filter { counts[$0] != nil }, id: \.self) { glyph in
                let count = counts[glyph] ?? 0
                HStack(spacing: DS.Space.xxs) {
                    Image(systemName: glyph.systemImage)
                        .symbolRenderingMode(.hierarchical)
                    Text(verbatim: "\(count)")
                        .monospacedDigit()
                }
                .help(glyph.count(count))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(glyph.count(count))
            }
        }
        .font(.dsCaption)
        .foregroundStyle(.dsTextTertiary)
    }
}
