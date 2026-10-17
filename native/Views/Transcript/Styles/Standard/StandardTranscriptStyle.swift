import ACP
import SwiftUI

/// The default transcript, Factory style: agent replies and tool activity in one column, tool
/// activity as one dense block, and the user's prompts in trailing bubbles.
nonisolated struct StandardTranscriptStyle: TranscriptStyle {
    @MainActor func makeBody(_ transcript: TranscriptStyleConfiguration) -> some View {
        let rows = transcript.rows
        let spacings = zip([nil] + rows.dropLast(), rows).map { previous, row in
            previous.map { spacing(between: $0, and: row) } ?? 0
        }
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(zip(rows, spacings)), id: \.0.id) { row, spacing in
                self.row(row, in: transcript)
                    .padding(.top, spacing)
            }
            if transcript.isWorking {
                WorkingIndicator()
                    .padding(.top, 16)
            }
        }
    }

    @MainActor @ViewBuilder
    private func row(_ row: TranscriptRow, in transcript: TranscriptStyleConfiguration) -> some View {
        switch row {
        case .exploration(let calls):
            transcript.exploration(calls)
        case .item(.message(let message)):
            MessageView(message: message)
        case .item(.toolCall(let call)):
            transcript.toolCall(call)
        case .item(.notice(let notice)):
            NoticeView(notice: notice)
        case .item(.subagent(let subagent)):
            transcript.subagent(subagent)
        case .item(.sessionMessage(let message)):
            transcript.sessionMessage(message)
        }
    }

    /// Tool activity reads as one dense block, Factory style; everything else gets room to breathe.
    @MainActor private func spacing(between previous: TranscriptRow, and next: TranscriptRow) -> CGFloat {
        previous.isToolActivity && next.isToolActivity ? 2 : 16
    }
}

extension TranscriptRow {
    /// Tool calls and folded runs of them.
    var isToolActivity: Bool {
        switch self {
        case .exploration, .item(.toolCall): true
        default: false
        }
    }
}

private struct WorkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Working…")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}
