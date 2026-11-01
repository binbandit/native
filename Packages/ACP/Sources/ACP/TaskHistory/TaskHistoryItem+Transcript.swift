import Foundation

extension TaskHistoryItem {
    /// The item as a transcript shows it where another agent's context was handed over: messages
    /// and tool calls, read-only. Reasoning, plans and turn endings stay out; they read as noise
    /// out of their own conversation.
    public var transcriptItem: TranscriptItem? {
        switch body {
        case .user(let message):
            var item = TranscriptMessage(role: .user, text: message.text)
            item.wasSteered = message.steered
            item.attachments = message.attachments.map { MessageAttachment(name: $0, url: nil) }
            return .message(item)
        case .agent(let text):
            return .message(TranscriptMessage(role: .agent, text: text))
        case .tool(let tool):
            var call = ToolCallState(id: tool.id)
            call.title = tool.title
            call.kind = ToolKind(rawValue: tool.kind) ?? .other
            call.status = Self.status(tool.status)
            call.locations = tool.paths.map { ToolCallLocation(path: $0) }
            call.rawInput = tool.input.map { .object(["command": .string($0)]) }
            call.content = tool.output.map { [.content(.text($0))] } ?? []
            return .toolCall(call)
        case .thought, .plan, .turnEnded, .unknown:
            return nil
        }
    }

    /// The inverse of how recording names a status; a name it doesn't know claims nothing.
    private static func status(_ name: String) -> ToolCallStatus {
        switch name {
        case "pending": .pending
        case "in_progress": .inProgress
        case "completed": .completed
        case "failed": .failed
        case "cancelled": .cancelled
        case "interrupted": .interrupted
        default: .unreported
        }
    }
}
