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

    /// Folds each run of two or more consecutive read/search calls into one row, the way the reference app
    /// shows "Explored 3 files". Calls waiting for approval stay on their own.
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

    @State private var isExpanded = false
    @State private var isHovering = false

    private var isRunning: Bool {
        calls.contains { !$0.status.isFinished }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.reveal) { isExpanded.toggle() }
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(calls, id: \.id) { call in
                        ToolCallView(call: call, onChoose: onChoose)
                    }
                }
                .padding(.leading, 12)
                .transition(RevealTransition())
            }
        }
    }

    private var summary: some View {
        let allReads = calls.allSatisfy { $0.name == "Read" || ($0.name == nil && $0.kind == .read) }
        let noun = allReads ? (calls.count == 1 ? "file" : "files") : (calls.count == 1 ? "search" : "searches")
        return HStack(spacing: 6) {
            Image(systemName: "text.magnifyingglass")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .font(.callout)
                .frame(width: 16)
            Text(isRunning ? "Exploring" : "Explored")
                .foregroundStyle(isHovering ? .primary : .secondary)
                .shimmering(isRunning)
            Text(verbatim: "\(calls.count) \(noun)")
                .monospacedDigit()
                .foregroundStyle(isHovering ? .primary : .tertiary)
            DisclosureChevron(isExpanded: isExpanded)
                .opacity(isHovering ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
        .animation(.easeOut(duration: 0.1), value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "Collapses the calls" : "Shows the calls")
    }
}

private extension ToolCallState {
    /// Reads and searches: the calls the reference app folds into exploration summaries.
    var isExploration: Bool {
        guard permission == nil else { return false }
        switch name {
        case "Read", "Grep", "Glob", "LS", "WebSearch": return true
        case nil: return kind == .read || kind == .search
        default: return false
        }
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
