import ACP
import SwiftUI

/// A transcript row: an item as is, or a run of read and search calls folded together.
enum TranscriptRow: Identifiable {
    case item(TranscriptItem)
    case exploration([ToolCallState])

    var id: String {
        switch self {
        case .item(let item): item.id
        // The first call never changes as the run grows, so the row keeps its identity.
        case .exploration(let calls): "exploration-\(calls.first?.id ?? "")"
        }
    }

    /// How many transcript items the row shows.
    var itemCount: Int {
        switch self {
        case .item: 1
        case .exploration(let calls): calls.count
        }
    }

    /// Work rows an earlier turn folds away: tool calls and reasoning. Prose and requests waiting
    /// for the user never fold.
    var isFoldableActivity: Bool {
        switch self {
        case .exploration: true
        case .item(.toolCall(let call)): call.permission == nil
        case .item(.message(let message)): message.role == .thought
        case .item: false
        }
    }

    /// Folds each run of two or more consecutive read/search calls into one summary row, so a burst
    /// of exploring doesn't push the work off screen. Calls waiting for approval stay on their own.
    static func rows(from items: [TranscriptItem]) -> [TranscriptRow] {
        var rows: [TranscriptRow] = []
        var run: [ToolCallState] = []

        func flush() {
            if run.count > 1 {
                rows.append(.exploration(run))
            } else {
                rows += run.map { TranscriptRow.item(.toolCall($0)) }
            }
            run.removeAll()
        }

        for item in items {
            if case .toolCall(let call) = item, call.isExploration {
                run.append(call)
            } else {
                flush()
                rows.append(.item(item))
            }
        }
        flush()
        return rows
    }
}

/// Consecutive read and search calls as one summary row ("Explored 3 files", "Exploring 2
/// searches" while one still runs) that expands into the individual rows.
struct ToolActivityGroupView: View {
    let calls: [ToolCallState]
    let onChoose: (PermissionOption) -> Void

    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?
    /// For groups shown outside a transcript, which has no `TranscriptDisclosures`.
    @State private var isOpenHere = false
    @State private var isHovering = false

    private var id: String {
        TranscriptRow.exploration(calls).id
    }

    private var isExpanded: Bool {
        disclosures?.isOpen(id) ?? isOpenHere
    }

    private var isRunning: Bool {
        calls.contains { !$0.status.isFinished }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.reveal) {
                    if let disclosures {
                        disclosures.toggle(id)
                    } else {
                        isOpenHere.toggle()
                    }
                }
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .trackHover($isHovering)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(calls, id: \.id) { call in
                        ToolCallView(call: call, onChoose: onChoose)
                            .equatable()
                    }
                }
                .padding(.leading, DS.Space.lg)
                .transition(RevealTransition())
            }
        }
    }

    private var summary: some View {
        let allReads = calls.allSatisfy { $0.category == .read }
        let noun = allReads ? (calls.count == 1 ? "file" : "files") : (calls.count == 1 ? "search" : "searches")
        return HStack(spacing: DS.Space.sm) {
            Image(systemName: (allReads ? DSToolGlyph.read : .search).systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.dsTextSecondary)
                .font(.dsBody)
                .frame(width: DS.Size.rowLeading)
            Text(isRunning ? "Exploring" : "Explored")
                .foregroundStyle(isHovering ? Color.dsTextPrimary : .dsTextSecondary)
                .shimmering(isRunning)
            Text(verbatim: "\(calls.count) \(noun)")
                .monospacedDigit()
                .foregroundStyle(isHovering ? Color.dsTextPrimary : .dsTextTertiary)
            DisclosureChevron(isExpanded: isExpanded)
                .opacity(isHovering || isExpanded || DS.isTouchPlatform ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.xs)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
        .accessibilityHint(isExpanded ? "Collapses the calls" : "Shows the calls")
    }
}

private extension ToolCallState {
    /// Reads and searches: the calls that fold into exploration summaries.
    var isExploration: Bool {
        permission == nil && (category == .read || category == .search)
    }
}

#if DEBUG
#Preview("Exploration group") {
    let calls = TranscriptFixtures.toolCalls.filter { ["Read", "Grep", "Glob"].contains($0.name) }
    VStack(alignment: .leading) {
        ToolActivityGroupView(calls: calls) { _ in }
    }
    .padding(20)
    .frame(width: 640, alignment: .leading)
}
#endif
