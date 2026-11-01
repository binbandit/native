import Foundation

extension SessionState {
    mutating func applyCompaction(_ update: CompactionUpdate, receivedAt: Date, transcriptDate: Date?) {
        guard let status = update.status.toolStatus else { return }
        if update.status == .completed, completedCompactions.insert(update.compactionId).inserted {
            contextCompactedAt = receivedAt
            usage = nil
        }
        var call = ToolCallUpdate(
            toolCallId: compactionToolID(update.compactionId), title: "Compact conversation", kind: .think,
            status: status)
        if let summary = update.summary {
            call.content = summary.map(ToolCallContent.content)
        }
        if let error = update.error {
            call.content = (call.content ?? []) + [.content(.text(error))]
        }
        upsertToolCall(call, at: transcriptDate)
    }

    mutating func appendCompactionSummary(_ chunk: CompactionSummaryChunk, at date: Date?) {
        let id = compactionToolID(chunk.compactionId)
        var content: [ToolCallContent] = []
        if let index = toolCallIndices[id], case .toolCall(let call) = items[index] {
            content = call.content
        }
        if case .text(let next) = chunk.content, case .content(.text(let previous))? = content.last {
            content[content.count - 1] = .content(.text(previous + next))
        } else {
            content.append(.content(chunk.content))
        }
        var call = ToolCallUpdate(toolCallId: id, title: "Compact conversation", kind: .think)
        call.content = content
        upsertToolCall(call, at: date)
    }

    private func compactionToolID(_ id: String) -> String { "compaction:\(id)" }
}
