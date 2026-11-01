import Foundation

/// Turns a session's transcript into history items: the provider-neutral record of a turn that any
/// agent can be told about later. Whole items, each capped, so the history grows with the
/// conversation and not with tool output. Native's own notices and messages between sessions stay
/// out; a subagent is kept as the work it was handed.
public enum TaskHistoryRecording {
    /// The most of a message or reply that's kept.
    public static let textLimit = 16_000
    /// The most of a thought that's kept: it shows how the agent got somewhere, not what it did.
    public static let thoughtLimit = 4_000
    /// The most of a tool's input or output that's kept.
    public static let toolLimit = 2_000

    /// The items for transcript entries, in order. User messages here are ones steered into the turn
    /// (or replayed history); a turn's own prompt is recorded when it's sent (`user(_:)`).
    public static func bodies(_ items: some Sequence<TranscriptItem>) -> [TaskHistoryItem.Body] {
        items.compactMap { item in
            switch item {
            case .message(let message):
                body(message)
            case .toolCall(let call):
                .tool(tool(call))
            case .subagent(let subagent):
                .tool(
                    TaskHistoryItem.Tool(
                        id: "subagent-\(subagent.id.rawValue)", title: subagent.title ?? "Subagent",
                        kind: "subagent", status: subagent.workState?.isWorking == true ? "in_progress" : "completed",
                        input: subagent.description.map { capped($0, toolLimit) }))
            case .notice, .sessionMessage:
                nil
            }
        }
    }

    /// A message the agent received as a turn's prompt.
    public static func user(
        _ text: String, attachments: [String] = [], origin: String, steered: Bool = false
    ) -> TaskHistoryItem.Body {
        .user(.init(text: capped(text, textLimit), attachments: attachments, origin: origin, steered: steered))
    }

    /// The plan as it stands, unless it's empty.
    public static func plan(_ entries: [PlanEntry]) -> TaskHistoryItem.Body? {
        guard !entries.isEmpty else { return nil }
        return .plan(
            entries.map {
                TaskHistoryItem.PlanStep(content: capped($0.content, toolLimit), status: $0.status.rawValue)
            })
    }

    private static func body(_ message: TranscriptMessage) -> TaskHistoryItem.Body? {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch message.role {
        case .user:
            guard !text.isEmpty || !message.attachments.isEmpty else { return nil }
            return user(
                text, attachments: message.attachments.map(\.name), origin: "user", steered: message.wasSteered)
        case .agent:
            return text.isEmpty ? nil : .agent(capped(text, textLimit))
        case .thought:
            return text.isEmpty ? nil : .thought(capped(text, thoughtLimit))
        }
    }

    private static func tool(_ call: ToolCallState) -> TaskHistoryItem.Tool {
        let printed =
            call.terminalOutput
            ?? call.content.compactMap { content -> String? in
                if case .content(let block) = content { block.text } else { nil }
            }.joined(separator: "\n").nonEmpty
            ?? call.rawOutput?.stringValue
        let edited = call.content.compactMap { content -> String? in
            if case .diff(let diff) = content { diff.path } else { nil }
        }
        var seen = Set<String>()
        return TaskHistoryItem.Tool(
            id: call.id, title: capped(call.title, toolLimit), kind: call.kind.rawValue, status: status(call.status),
            paths: (call.locations.map(\.path) + edited).filter { seen.insert($0).inserted },
            input: call.shellCommand.map { capped($0, toolLimit) },
            output: printed?.nonEmpty.map { capped($0, toolLimit) })
    }

    private static func status(_ status: ToolCallStatus) -> String {
        switch status {
        case .pending: "pending"
        case .inProgress: "in_progress"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        case .interrupted: "interrupted"
        case .unreported: "unreported"
        }
    }

    /// The start of `text`, with a note when it was cut.
    static func capped(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "\n[Truncated]"
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
