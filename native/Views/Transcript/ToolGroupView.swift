import ACP
import SwiftUI

/// A run of tool work as one line (`ToolWorkGroup`). While the turn is on it, the line is what the
/// agent is doing now ("Reading ToolRow.swift", "Thinking"); once it's done, what it did ("Read 3
/// files, edited 1 file and ran 2 commands"), and how its last call ended if that wasn't well. It
/// opens into its calls and reasoning, which scroll past a dozen rows and, while the group is live,
/// follow the newest one unless the user scrolled back.
struct ToolGroupView: View, Equatable {
    let group: ToolWorkGroup
    /// The turn is still working on this group.
    let isLive: Bool
    /// When each thought in the group started and ended, by its index in `group.items`.
    var thinking: [Int: ThinkingClock] = [:]

    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?
    @Environment(\.toolWorkspaceRoot) private var root
    /// For groups shown outside a transcript, which has no `TranscriptDisclosures`.
    @State private var isOpenHere = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.group == rhs.group && lhs.isLive == rhs.isLive && lhs.thinking == rhs.thinking
    }

    private var isOpen: Bool {
        disclosures?.isOpen(group.id) ?? isOpenHere
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                ToolGroupList(group: group, isLive: isLive, thinking: thinking)
                    .transition(RevealTransition())
            }
        }
    }

    @ViewBuilder private var header: some View {
        let toggle = {
            withAnimation(.reveal) {
                if let disclosures {
                    disclosures.toggle(group.id)
                } else {
                    isOpenHere.toggle()
                }
            }
        }
        if isLive, let live = liveLine {
            ToolLine(
                glyph: live.glyph, sentence: live.sentence, isBusy: live.isBusy, isExpandable: true,
                isExpanded: isOpen, help: live.call?.wording.detail, accessibilityStatus: "Running", toggle: toggle
            ) {
                ToolLineStatus(phase: .running, outcome: nil, startedAt: live.call?.startedAt)
            }
        } else {
            let calls = group.calls
            let outcome = group.outcome
            ToolLine(
                glyph: ToolWorkSummary.sharedCategory(of: calls)?.glyph ?? .mixed,
                sentence: group.summary, stats: stats(of: calls), isExpandable: true, isExpanded: isOpen,
                accessibilityStatus: outcome.flatMap { $0.outcome(exitCode: calls.last?.exitCode) },
                toggle: toggle
            ) {
                if let outcome {
                    ToolLineStatus(phase: outcome, outcome: outcome.outcome(exitCode: calls.last?.exitCode))
                }
            }
        }
    }

    private struct LiveLine {
        var glyph: DSToolGlyph
        var sentence: String
        var isBusy: Bool
        var call: ToolCallState?
    }

    /// What the agent is doing now: the call that's running, else thinking when the group ends in
    /// reasoning, else the call it finished last while it decides what's next.
    private var liveLine: LiveLine? {
        if case .message(let message)? = group.items.last, message.role == .thought,
            !group.calls.contains(where: { !$0.status.isFinished })
        {
            return LiveLine(glyph: .think, sentence: "Thinking", isBusy: true)
        }
        guard let call = group.currentCall else { return nil }
        let presentation = ToolPresentation(call, root: root)
        return LiveLine(
            glyph: presentation.glyph, sentence: presentation.sentence, isBusy: true, call: call)
    }

    /// What the group's edits changed, when it made any.
    private func stats(of calls: [ToolCallState]) -> DiffStats? {
        let changes = calls.compactMap { $0.status == .completed ? $0.wording.lineChanges : nil }
        guard !changes.isEmpty else { return nil }
        return changes.reduce(DiffStats()) { $0 + DiffStats(added: $1.added, removed: $1.removed) }
    }
}

/// An open group's calls and reasoning, under its line. Past `maxVisibleRows` it scrolls, unless a
/// row in it is open: then it shows in full, so a panel never scrolls inside a list that scrolls.
private struct ToolGroupList: View {
    let group: ToolWorkGroup
    let isLive: Bool
    let thinking: [Int: ThinkingClock]

    /// About a dozen rows, so the cut-off one says the list scrolls.
    static let maxVisibleRows = 12

    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?
    /// Whether the list shows its end, so new calls should scroll into view.
    @State private var isFollowing = true
    @State private var isScrolledDown = false
    @State private var position = ScrollPosition(edge: .bottom)

    var body: some View {
        let isCapped =
            group.items.count > Self.maxVisibleRows
            && !group.calls.contains { disclosures?.isOpen($0.id) == true }
        Group {
            if isCapped {
                capped
            } else {
                rows
            }
        }
        // Under the line's sentence, as the line's own.
        .padding(.leading, DS.Size.rowLeading + DS.Space.sm)
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(group.items.indices, id: \.self) { index in
                row(group.items[index], at: index)
            }
        }
    }

    private var capped: some View {
        ScrollView(.vertical) {
            rows
        }
        .scrollPosition($position)
        .defaultScrollAnchor(isLive ? .bottom : .top, for: .initialOffset)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: ToolGroupScrollState.self) { [threshold = DS.Space.lg] geometry in
            ToolGroupScrollState(
                contentHeight: geometry.contentSize.height,
                isAtStart: geometry.visibleRect.minY <= 1,
                isAtEnd: geometry.visibleRect.maxY >= geometry.contentSize.height - threshold)
        } action: { old, new in
            // A new call moves the end away without the user doing anything; only their scrolling
            // decides whether the list follows.
            if new.contentHeight == old.contentHeight, isFollowing != new.isAtEnd {
                isFollowing = new.isAtEnd
            }
            if isScrolledDown == new.isAtStart {
                isScrolledDown = !new.isAtStart
            }
        }
        .onChange(of: group.items.count) {
            if isLive, isFollowing { position.scrollTo(edge: .bottom) }
        }
        .frame(height: TranscriptMetrics.toolGroupListHeight)
        // Rows cut off where the list scrolls fade rather than being sliced through.
        .dsEdgeFade(fadedEdges)
    }

    private var fadedEdges: Edge.Set {
        var edges: Edge.Set = []
        if isScrolledDown { edges.insert(.top) }
        if !isFollowing || !isLive { edges.insert(.bottom) }
        return edges
    }

    @ViewBuilder private func row(_ item: TranscriptItem, at index: Int) -> some View {
        switch item {
        case .toolCall(let call):
            // Requests waiting on the user end a group, so none of these answers one.
            ToolCallView(call: call) { _ in }
                .equatable()
                .environment(\.permissionShortcutsEnabled, false)
        case .message(let message):
            // In line with the tool rows: reasoning gets the think glyph in their glyph column.
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                Image(systemName: DSToolGlyph.think.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.dsTextTertiary)
                    .font(.dsBody)
                    .frame(width: DS.Size.rowLeading)
                    .accessibilityHidden(true)
                MessageView(message: message, thinking: thinking[index])
                    .equatable()
            }
            .padding(.vertical, DS.Space.xs)
        case .notice, .subagent, .sessionMessage:
            // Groups hold only tool calls and reasoning.
            EmptyView()
        }
    }
}

private struct ToolGroupScrollState: Equatable {
    var contentHeight: CGFloat
    var isAtStart: Bool
    var isAtEnd: Bool
}

#if DEBUG
#Preview("Tool group - Done, closed and opened") {
    let groups = ToolGroupPreviewFixtures.done
    let disclosures = TranscriptDisclosures()
    if let opened = groups.last { disclosures.toggle(opened.id) }
    return DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(groups) { group in
                ToolGroupView(group: group, isLive: false)
            }
        }
        .environment(disclosures)
        .padding(DS.Space.xl)
        .frame(width: 620)
    }
}

#Preview("Tool group - Live") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ToolGroupView(group: ToolGroupPreviewFixtures.running, isLive: true)
            ToolGroupView(group: ToolGroupPreviewFixtures.thinking, isLive: true)
        }
        .padding(DS.Space.xl)
        .frame(width: 620)
    }
}

#Preview("Tool group - Failed and stopped") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach(ToolGroupPreviewFixtures.troubled) { group in
                ToolGroupView(group: group, isLive: false)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: 620)
    }
}

#Preview("Tool group - Long, opened") {
    let group = ToolGroupPreviewFixtures.long
    let disclosures = TranscriptDisclosures()
    disclosures.toggle(group.id)
    return DSPreviewPair {
        ToolGroupView(group: group, isLive: false)
            .environment(disclosures)
            .padding(DS.Space.xl)
            .frame(width: 620)
    }
}
#endif
