import Foundation

/// Everything a client shows for one session, folded from the agent's `session/update`s plus the
/// client's own actions (sending prompts, answering permission requests).
public struct SessionState: Sendable {
    public var title: String?
    public private(set) var items: [TranscriptItem] = []
    /// The agent's latest plan; each `plan` update replaces the previous one.
    public private(set) var plan: [PlanEntry] = []
    public var configOptions: [ConfigOption] = []
    public private(set) var availableCommands: [AvailableCommand] = []
    public private(set) var usage: Usage?

    private var toolCallIndices: [String: Int] = [:]
    private var subagentIndices: [SessionID: Int] = [:]
    private var sessionMessageIndices: [String: Int] = [:]

    public init() {}

    public mutating func apply(_ update: SessionUpdate) {
        switch update {
        case .userMessageChunk(let chunk): appendChunk(chunk, role: .user)
        case .agentMessageChunk(let chunk): appendChunk(chunk, role: .agent)
        case .agentThoughtChunk(let chunk): appendChunk(chunk, role: .thought)
        case .toolCall(let update), .toolCallUpdate(let update): upsertToolCall(update)
        case .plan(let entries): plan = entries
        case .availableCommands(let commands): availableCommands = commands
        case .configOptions(let options): configOptions = options
        case .currentMode(let mode):
            // Agents that report modes this way still list them as the `mode` config option.
            if let index = configOptions.firstIndex(where: { $0.category == "mode" || $0.id == "mode" }),
               case .select(_, let choices) = configOptions[index].kind,
               choices.contains(where: { $0.value == mode }) {
                configOptions[index].kind = .select(currentValue: mode, options: choices)
            }
        case .sessionInfo(let title): self.title = title ?? self.title
        case .usage(var usage):
            // Agents may report cost only now and then; keep the last known figure.
            usage.cost = usage.cost ?? self.usage?.cost
            self.usage = usage
        case .subagent(let update): upsertSubagent(update)
        case .sessionMessage(let update):
            upsertSessionMessage(update.messageId, sender: update.senderSessionId, recipient: update.recipientSessionId) { message in
                message.content = update.content.applied(to: message.content) ?? []
            }
        case .sessionMessageChunk(let chunk):
            upsertSessionMessage(chunk.messageId, sender: chunk.senderSessionId, recipient: chunk.recipientSessionId) { message in
                // Streamed text continues the block it belongs to rather than starting a paragraph.
                if case .text(let next) = chunk.content, case .text(let previous)? = message.content.last {
                    message.content[message.content.count - 1] = .text(previous + next)
                } else {
                    message.content.append(chunk.content)
                }
            }
        case .unsupported: break
        }
    }

    /// The subagents this session has started, in the order they were announced.
    public var subagents: [SubagentState] {
        items.compactMap { item in
            if case .subagent(let subagent) = item { subagent } else { nil }
        }
    }

    /// Records a prompt the user sent. Agents don't echo live prompts back, only on replay.
    /// `steered` marks a message added to a turn already in progress.
    public mutating func appendUserMessage(_ text: String, steered: Bool = false) {
        items.append(.message(TranscriptMessage(role: .user, text: text, wasSteered: steered)))
    }

    public mutating func appendNotice(_ text: String, isError: Bool) {
        items.append(.notice(TranscriptNotice(text: text, isError: isError)))
    }

    public mutating func requestPermission(_ request: RequestPermissionRequest, id: RequestID) {
        // The request carries the tool call's latest details, which may be newer than the last update.
        upsertToolCall(request.toolCall)
        guard let index = toolCallIndices[request.toolCall.toolCallId], case .toolCall(var call) = items[index] else { return }
        call.permission = PendingPermission(requestID: id, options: request.options)
        items[index] = .toolCall(call)
    }

    /// Clears a permission request once it's been answered and returns it.
    @discardableResult
    public mutating func resolvePermission(toolCallID: String) -> PendingPermission? {
        guard let index = toolCallIndices[toolCallID], case .toolCall(var call) = items[index] else { return nil }
        let permission = call.permission
        call.permission = nil
        items[index] = .toolCall(call)
        return permission
    }

    public var pendingPermissions: [(toolCallID: String, permission: PendingPermission)] {
        items.compactMap { item in
            guard case .toolCall(let call) = item, let permission = call.permission else { return nil }
            return (call.id, permission)
        }
    }

    /// Wraps up a prompt turn. ACP v1 has no status for tool calls a cancellation interrupted, so
    /// they're marked here; any stop other than a normal one is noted in the transcript.
    public mutating func endTurn(_ stopReason: StopReason) {
        if stopReason == .cancelled {
            for index in toolCallIndices.values {
                guard case .toolCall(var call) = items[index], !call.status.isFinished else { continue }
                call.status = .cancelled
                call.permission = nil
                items[index] = .toolCall(call)
            }
        }
        switch stopReason {
        case .endTurn: break
        case .cancelled: appendNotice("Stopped.", isError: false)
        case .maxTokens: appendNotice("Stopped: the response hit the token limit.", isError: true)
        case .maxTurnRequests: appendNotice("Stopped: the turn hit its request limit.", isError: true)
        case .refusal: appendNotice("The agent declined to continue.", isError: true)
        case .error: appendNotice("The turn failed.", isError: true)
        case .other(let reason): appendNotice("Stopped: \(reason).", isError: true)
        }
    }

    // MARK: - Folding

    private mutating func appendChunk(_ chunk: ContentChunk, role: TranscriptMessage.Role) {
        let text: String
        switch chunk.content {
        case .text(let string): text = string
        case .image: text = "[Image]"
        case .resourceLink(let uri, _), .resource(let uri, _): text = uri
        case .unsupported(let type): text = "[\(type)]"
        }
        // Continue the last message when it has the same role and, if the agent sends ids, the same id.
        if case .message(var last) = items.last, last.role == role, chunk.messageId == nil || chunk.messageId == last.messageID {
            last.text += text
            items[items.count - 1] = .message(last)
        } else {
            items.append(.message(TranscriptMessage(role: role, text: text, messageID: chunk.messageId)))
        }
    }

    private mutating func upsertSubagent(_ update: SubagentUpdate) {
        // The first announcement fixes the subagent's place in the transcript; later updates patch it.
        var subagent = subagentIndices[update.sessionId].flatMap { index in
            if case .subagent(let subagent) = items[index] { subagent } else { nil }
        } ?? SubagentState(id: update.sessionId)
        subagent.title = update.title.applied(to: subagent.title)
        subagent.description = update.description.applied(to: subagent.description)
        subagent.canCancel = update.canCancel.applied(to: subagent.canCancel) ?? false
        subagent.workState = update.state.applied(to: subagent.workState)
        if let index = subagentIndices[update.sessionId] {
            items[index] = .subagent(subagent)
        } else {
            subagentIndices[update.sessionId] = items.count
            items.append(.subagent(subagent))
        }
    }

    private mutating func upsertSessionMessage(_ messageID: String, sender: SessionID?, recipient: SessionID?, change: (inout SessionMessage) -> Void) {
        var message = sessionMessageIndices[messageID].flatMap { index in
            if case .sessionMessage(let message) = items[index] { message } else { nil }
        } ?? SessionMessage(id: messageID)
        // Participants fill in as they become known; a missing one never clears an earlier value.
        message.sender = sender ?? message.sender
        message.recipient = recipient ?? message.recipient
        change(&message)
        if let index = sessionMessageIndices[messageID] {
            items[index] = .sessionMessage(message)
        } else {
            sessionMessageIndices[messageID] = items.count
            items.append(.sessionMessage(message))
        }
    }

    private mutating func upsertToolCall(_ update: ToolCallUpdate) {
        if let index = toolCallIndices[update.toolCallId], case .toolCall(var call) = items[index] {
            call.merge(update)
            items[index] = .toolCall(call)
        } else {
            var call = ToolCallState(id: update.toolCallId)
            call.merge(update)
            toolCallIndices[update.toolCallId] = items.count
            items.append(.toolCall(call))
        }
    }
}

// MARK: - Transcript items

public enum TranscriptItem: Identifiable, Hashable, Sendable {
    case message(TranscriptMessage)
    case toolCall(ToolCallState)
    case notice(TranscriptNotice)
    case subagent(SubagentState)
    case sessionMessage(SessionMessage)

    public var id: String {
        switch self {
        case .message(let message): message.id.uuidString
        case .toolCall(let call): "tool-\(call.id)"
        case .notice(let notice): notice.id.uuidString
        case .subagent(let subagent): "subagent-\(subagent.id)"
        case .sessionMessage(let message): "session-message-\(message.id)"
        }
    }
}

/// A subagent's entry in its parent's transcript. Its own conversation is a separate session.
public struct SubagentState: Hashable, Sendable, Identifiable {
    public let id: SessionID
    public var title: String?
    public var description: String?
    public var workState: SubagentWorkState?
    public var canCancel = false
}

/// A message between two sessions, such as the task a parent hands its subagent. Compare the
/// participants with the transcript's own session to tell incoming from outgoing.
public struct SessionMessage: Hashable, Sendable {
    public let id: String
    public var sender: SessionID?
    public var recipient: SessionID?
    public var content: [ContentBlock] = []

    public var text: String {
        content.compactMap(\.text).joined(separator: "\n\n")
    }
}

public struct TranscriptMessage: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case user, agent, thought
    }

    /// Local identity; agents can reuse a message id across several transcript items.
    public let id = UUID()
    public var role: Role
    public var text: String
    public var messageID: String?
    /// A user message sent into a turn that was already running.
    public var wasSteered = false
}

public struct TranscriptNotice: Hashable, Sendable {
    public let id = UUID()
    public var text: String
    public var isError: Bool
}

public struct ToolCallState: Hashable, Sendable {
    public let id: String
    public var title = "Tool call"
    public var name: String?
    public var kind: ToolKind = .other
    public var status: ToolCallStatus = .pending
    public var content: [ToolCallContent] = []
    public var locations: [ToolCallLocation] = []
    public var rawInput: JSONValue?
    public var rawOutput: JSONValue?
    /// Set while the agent waits for the user to approve this call.
    public var permission: PendingPermission?

    mutating func merge(_ update: ToolCallUpdate) {
        if let title = update.title { self.title = title }
        if let name = update.name { self.name = name }
        if let kind = update.kind { self.kind = kind }
        if let status = update.status { self.status = status }
        if let content = update.content { self.content = content }
        if let locations = update.locations { self.locations = locations }
        if let rawInput = update.rawInput { self.rawInput = rawInput }
        if let rawOutput = update.rawOutput { self.rawOutput = rawOutput }
    }
}

public struct PendingPermission: Hashable, Sendable {
    public var requestID: RequestID
    public var options: [PermissionOption]
}
