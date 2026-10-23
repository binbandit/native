import Foundation

/// Everything a client shows for one session, folded from the agent's `session/update`s plus the
/// client's own actions (sending prompts, answering permission requests).
public struct SessionState: Sendable {
    public var title: String?
    /// Changed only through `appendItem(_:)` and `replaceItem(at:with:)`, which keep the indexes
    /// below up to date.
    public private(set) var items: [TranscriptItem] = []
    /// The agent's latest plan; each `plan` update replaces the previous one.
    public private(set) var plan: [PlanEntry] = []
    public var configOptions: [ConfigOption] = []
    public private(set) var availableCommands: [AvailableCommand] = []
    public private(set) var usage: Usage?

    private var toolCallIndices: [String: Int] = [:]
    /// Tool calls that haven't finished, so a turn's end settles them without a pass over every call.
    var openCallIndices: Set<Int> = []
    /// The clocks of live turns, keyed by the index of the prompt that started each one.
    var turnClocks: [Int: TurnClock] = [:]
    /// Where the running live turn starts. Only its items get times; replayed history has none.
    var openTurn: Int?
    /// A message failed for a passing reason and waits for Native to send it again
    /// (`failTurn(_:retry:at:)`).
    var isAwaitingRetry = false
    /// The live turn that message started, when the transcript shows it: not running, but not over
    /// either.
    var suspendedTurn: Int?
    /// The notice following the message Native is sending again, until the retry settles.
    var retryNoticeIndex: Int?
    /// A stop ended the latest turn and nothing has started since, so what the agent sends next came
    /// after the stop (`TranscriptTurn.isLateOutput`).
    var isAfterStop = false
    /// How replayed turns that the agent's history says were stopped ended, keyed like `turnClocks`.
    var replayedStops: [Int: StopReason] = [:]
    private var subagentIndices: [SessionID: Int] = [:]
    private var sessionMessageIndices: [String: Int] = [:]
    // Kept as items change, so what a transcript asks for on every update costs the size of the
    // answer rather than a pass over thousands of items.
    /// The prompts that start turns: every user message that wasn't steered into a running one.
    private(set) var promptIndices: [Int] = []
    /// Where turns start: at every prompt, and where output an agent sent after a stop begins.
    var turnStarts: [Int] = []
    /// The turns of output an agent sent after its turn was stopped, by where each starts.
    var lateOutputStarts: Set<Int> = []
    /// What each turn's items did, by the index of the turn's first item.
    private var turnSummaries: [Int: TurnSummary] = [:]
    /// Tool calls waiting for permission, in transcript order.
    private var permissionIndices: [Int] = []
    /// How many times each turn's items changed, by the index of the turn's first item.
    private var turnRevisions: [Int: Int] = [:]
    /// Completed tool calls of the kinds that may write files.
    private var completedWriteIndices: Set<Int> = []

    public init() {}

    /// Folds one update in. `date` is when it arrived; only items of a live turn keep it.
    public mutating func apply(_ update: SessionUpdate, at date: Date = .now) {
        let date = openTurn == nil ? nil : date
        switch update {
        case .userMessageChunk(let chunk):
            if let marker = InterruptionMarker(chunk) {
                recordReplayedStop(marker)
            } else if openTurn == nil, case .text(let text) = chunk.content, let prompt = RecoveryPrompt(replayed: text)
            {
                recordReplayedRecovery(prompt, text: text)
            } else {
                appendChunk(chunk, role: .user, at: date)
            }
        case .agentMessageChunk(let chunk): appendChunk(chunk, role: .agent, at: date)
        case .agentThoughtChunk(let chunk): appendChunk(chunk, role: .thought, at: date)
        case .toolCall(let update), .toolCallUpdate(let update): upsertToolCall(update, at: date)
        case .plan(let entries): plan = entries
        case .availableCommands(let commands): availableCommands = commands
        case .configOptions(let options): configOptions = options
        case .currentMode(let mode):
            // Agents that report modes this way still list them as the `mode` config option.
            if let index = configOptions.firstIndex(where: { $0.category == "mode" || $0.id == "mode" }),
                case .select(_, let choices) = configOptions[index].kind,
                choices.contains(where: { $0.value == mode })
            {
                configOptions[index].kind = .select(currentValue: mode, options: choices)
            }
        case .sessionInfo(let title): self.title = title ?? self.title
        case .usage(var usage):
            // Agents may report cost only now and then; keep the last known figure.
            usage.cost = usage.cost ?? self.usage?.cost
            self.usage = usage
        case .subagent(let update): upsertSubagent(update)
        case .sessionMessage(let update):
            upsertSessionMessage(update.messageId, sender: update.senderSessionId, recipient: update.recipientSessionId)
            { message in
                message.content = update.content.applied(to: message.content) ?? []
            }
        case .sessionMessageChunk(let chunk):
            upsertSessionMessage(chunk.messageId, sender: chunk.senderSessionId, recipient: chunk.recipientSessionId) {
                message in
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
        subagentIndices.values.sorted().compactMap { index in
            if case .subagent(let subagent) = items[index] { subagent } else { nil }
        }
    }

    public var hasSubagents: Bool {
        !subagentIndices.isEmpty
    }

    /// Records a prompt the user sent. Agents don't echo live prompts back, only on replay.
    /// `steered` marks a message added to a turn already in progress; any other prompt starts a live
    /// turn, timed from `date` until `endTurn`. `preamble` marks instructions that went ahead of it.
    public mutating func appendUserMessage(
        _ text: String, attachments: [MessageAttachment] = [], preamble: PromptPreamble.Marker? = nil,
        steered: Bool = false, at date: Date = .now
    ) {
        if !steered {
            // A new turn ends the wait for a retry; the message waiting is no longer next.
            stopRetrying(at: date)
            openTurn = items.count
            turnClocks[items.count] = TurnClock(startedAt: date)
        }
        var message = TranscriptMessage(role: .user, text: text, wasSteered: steered, startedAt: date, updatedAt: date)
        message.attachments = attachments
        message.preamble = preamble
        appendItem(.message(message))
    }

    /// The instructions the agent had last (`PromptPreamble`): the newest prompt's that carried
    /// any. A live turn that failed, or waits to be sent again, doesn't count, since its prompt may
    /// never have reached the agent.
    public var deliveredPreamble: PromptPreamble.Marker? {
        for index in promptIndices.reversed() {
            guard case .message(let message) = items[index], let marker = message.preamble,
                turnClocks[index]?.stopReason != .error, turnClocks[index]?.suspendedAt == nil
            else { continue }
            return marker
        }
        return nil
    }

    public mutating func appendNotice(_ text: String, isError: Bool) {
        appendItem(.notice(TranscriptNotice(text: text, isError: isError)))
    }

    public mutating func requestPermission(_ request: RequestPermissionRequest, id: RequestID, at date: Date = .now) {
        // The request carries the tool call's latest details, which may be newer than the last update.
        upsertToolCall(request.toolCall, at: openTurn == nil ? nil : date)
        guard let index = toolCallIndices[request.toolCall.toolCallId], case .toolCall(var call) = items[index] else {
            return
        }
        call.permission = PendingPermission(requestID: id, options: request.options)
        replaceItem(at: index, with: .toolCall(call))
    }

    /// Clears a permission request once it's been answered and returns it.
    @discardableResult
    public mutating func resolvePermission(toolCallID: String) -> PendingPermission? {
        guard let index = toolCallIndices[toolCallID], case .toolCall(var call) = items[index] else { return nil }
        let permission = call.permission
        call.permission = nil
        replaceItem(at: index, with: .toolCall(call))
        return permission
    }

    public var pendingPermissions: [(toolCallID: String, permission: PendingPermission)] {
        permissionRequests.compactMap { call in call.permission.map { (call.id, $0) } }
    }

    /// The tool calls waiting for the user's permission, oldest first.
    public var permissionRequests: [ToolCallState] {
        permissionIndices.compactMap { index in
            if case .toolCall(let call) = items[index] { call } else { nil }
        }
    }

    // MARK: - Indexing

    mutating func appendItem(_ item: TranscriptItem) {
        items.append(item)
        index(items.count - 1)
    }

    mutating func replaceItem(at index: Int, with item: TranscriptItem) {
        items[index] = item
        self.index(index)
    }

    /// Brings the indexes up to date with the item at `index`, which was just added or changed.
    private mutating func index(_ index: Int) {
        defer { turnRevisions[turnRange(containing: index).lowerBound, default: 0] += 1 }
        switch items[index] {
        case .message(let message) where message.role == .user && !message.wasSteered:
            // Only a new item starts a turn; a prompt growing chunk by chunk is already one.
            if promptIndices.last.map({ $0 < index }) ?? true {
                promptIndices.append(index)
                turnStarts.append(index)
                isAfterStop = false
            }
        case .toolCall(let call):
            if call.status.isFinished {
                openCallIndices.remove(index)
            } else {
                openCallIndices.insert(index)
            }
            let position = permissionIndices.firstIndex(of: index)
            if call.permission == nil, let position {
                permissionIndices.remove(at: position)
            } else if call.permission != nil, position == nil {
                permissionIndices.insert(
                    index, at: permissionIndices.firstIndex { $0 > index } ?? permissionIndices.endIndex)
            }
            if call.status == .completed, [.edit, .delete, .move, .execute].contains(call.kind) {
                completedWriteIndices.insert(index)
            } else {
                completedWriteIndices.remove(index)
            }
            summarizeTurn(containing: index)
        case .subagent:
            summarizeTurn(containing: index)
        case .message, .notice, .sessionMessage:
            break
        }
    }

    /// The items of the turn holding `index`, as `turns` splits them.
    func turnRange(containing index: Int) -> Range<Int> {
        guard let position = turnStarts.lastIndex(where: { $0 <= index }) else {
            // Before the first prompt: a turn of its own.
            return 0..<(turnStarts.first ?? items.count)
        }
        let next = position + 1 < turnStarts.count ? turnStarts[position + 1] : items.count
        return turnStarts[position]..<next
    }

    /// Counts again what the turn holding `index` did; only tool calls and subagents count.
    private mutating func summarizeTurn(containing index: Int) {
        let range = turnRange(containing: index)
        turnSummaries[range.lowerBound] = TurnSummary(items: items[range])
    }

    /// What `turn` did, counted when its items last changed.
    func cachedSummary(of turn: TranscriptTurn) -> TurnSummary? {
        turnSummaries[turn.items.lowerBound]
    }

    /// How many times the items of the turn starting at `start` changed.
    func revision(ofTurnAt start: Int) -> Int {
        turnRevisions[start] ?? 0
    }

    /// Completed tool calls that may have written files (edits, deletes, moves, commands), for
    /// noticing new writes without a pass over the transcript.
    public var completedWriteCount: Int {
        completedWriteIndices.count
    }

    // MARK: - Folding

    private mutating func appendChunk(_ chunk: ContentChunk, role: TranscriptMessage.Role, at date: Date?) {
        // A replayed prompt's instructions show as their marker, and begin the prompt they went with.
        if role == .user, case .text(let text) = chunk.content, let (preamble, rest) = PromptPreamble.leading(text) {
            var message = TranscriptMessage(
                role: .user, text: String(rest), messageID: chunk.messageId, startedAt: date, updatedAt: date)
            message.preamble = preamble.marker
            appendItem(.message(message))
            return
        }
        // Images and resources retain their bytes for every visible message role. Only user
        // replay text is interpreted as an attachment; ordinary reply text stays Markdown.
        let attachment: MessageAttachment? =
            switch (role, chunk.content) {
            case (.thought, _), (.agent, .text): nil
            default: MessageAttachment(chunk.content)
            }
        if var attachment {
            attachment.isLocalFile = role == .user
            if case .message(var last) = items.last, last.role == role,
                chunk.messageId == nil || chunk.messageId == last.messageID
            {
                if let url = attachment.url, let index = last.attachments.firstIndex(where: { $0.url == url }) {
                    last.attachments[index].imageData = attachment.imageData ?? last.attachments[index].imageData
                    last.attachments[index].embeddedData =
                        attachment.embeddedData ?? last.attachments[index].embeddedData
                    last.attachments[index].mimeType = attachment.mimeType ?? last.attachments[index].mimeType
                } else {
                    last.attachments.append(attachment)
                }
                last.updatedAt = date ?? last.updatedAt
                replaceItem(at: items.count - 1, with: .message(last))
            } else {
                if role != .user { beginLateOutputIfStopped() }
                var message = TranscriptMessage(
                    role: role, text: "", messageID: chunk.messageId, startedAt: date, updatedAt: date)
                message.attachments = [attachment]
                appendItem(.message(message))
            }
            return
        }
        let text: String
        switch chunk.content {
        case .text(let string): text = string
        case .image: text = "[Image]"
        case .resourceLink(let uri, _), .resource(let uri, _, _), .resourceBlob(let uri, _, _): text = uri
        case .unsupported(let type): text = "[\(type)]"
        }
        // Continue the last message when it has the same role and, if the agent sends ids, the same id.
        if case .message(var last) = items.last, last.role == role,
            chunk.messageId == nil || chunk.messageId == last.messageID
        {
            last.text += text
            last.updatedAt = date ?? last.updatedAt
            replaceItem(at: items.count - 1, with: .message(last))
        } else {
            if role != .user {
                beginLateOutputIfStopped()
            }
            let message = TranscriptMessage(
                role: role, text: text, messageID: chunk.messageId, startedAt: date, updatedAt: date)
            appendItem(.message(message))
        }
    }

    private mutating func upsertSubagent(_ update: SubagentUpdate) {
        // The first announcement fixes the subagent's place in the transcript; later updates patch it.
        var subagent =
            subagentIndices[update.sessionId].flatMap { index in
                if case .subagent(let subagent) = items[index] { subagent } else { nil }
            } ?? SubagentState(id: update.sessionId)
        subagent.title = update.title.applied(to: subagent.title)
        subagent.description = update.description.applied(to: subagent.description)
        subagent.canCancel = update.canCancel.applied(to: subagent.canCancel) ?? false
        subagent.workState = update.state.applied(to: subagent.workState)
        if let index = subagentIndices[update.sessionId] {
            replaceItem(at: index, with: .subagent(subagent))
        } else {
            beginLateOutputIfStopped()
            subagentIndices[update.sessionId] = items.count
            appendItem(.subagent(subagent))
        }
    }

    private mutating func upsertSessionMessage(
        _ messageID: String, sender: SessionID?, recipient: SessionID?, change: (inout SessionMessage) -> Void
    ) {
        var message =
            sessionMessageIndices[messageID].flatMap { index in
                if case .sessionMessage(let message) = items[index] { message } else { nil }
            } ?? SessionMessage(id: messageID)
        // Participants fill in as they become known; a missing one never clears an earlier value.
        message.sender = sender ?? message.sender
        message.recipient = recipient ?? message.recipient
        change(&message)
        if let index = sessionMessageIndices[messageID] {
            replaceItem(at: index, with: .sessionMessage(message))
        } else {
            beginLateOutputIfStopped()
            sessionMessageIndices[messageID] = items.count
            appendItem(.sessionMessage(message))
        }
    }

    private mutating func upsertToolCall(_ update: ToolCallUpdate, at date: Date?) {
        if let index = toolCallIndices[update.toolCallId], case .toolCall(var call) = items[index] {
            call.merge(update)
            if call.status.isFinished, call.finishedAt == nil, call.startedAt != nil {
                call.finishedAt = date
            }
            replaceItem(at: index, with: .toolCall(call))
        } else {
            beginLateOutputIfStopped()
            var call = ToolCallState(id: update.toolCallId)
            call.merge(update)
            call.startedAt = date
            if call.status.isFinished { call.finishedAt = date }
            toolCallIndices[update.toolCallId] = items.count
            appendItem(.toolCall(call))
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
    /// Files and images that went with a user message.
    public var attachments: [MessageAttachment] = []
    /// Instructions that went ahead of a user message (`PromptPreamble`), shown as a marker.
    public var preamble: PromptPreamble.Marker?
    /// When a live message began and last grew; nil for replayed history.
    public var startedAt: Date?
    public var updatedAt: Date?
}

public struct TranscriptNotice: Hashable, Sendable {
    public let id = UUID()
    public var text: String
    public var isError: Bool
    /// For the notice of a message Native is sending again: how far that got.
    public internal(set) var retry: Retry?
    /// What Native told the agent, for a notice that stands in for Native's own message in the
    /// agent's history (`RecoveryPrompt`).
    public internal(set) var sentToAgent: String?
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
    /// The agent's `_meta` for the call, every update's merged in.
    public var meta: JSONValue?
    /// What a command printed, from the output chunks in its `_meta` (see `appendingTerminalOutput`).
    public var terminalOutput: String?
    /// When a live call was first announced and when it finished; nil for replayed history.
    public var startedAt: Date?
    public var finishedAt: Date?

    mutating func merge(_ update: ToolCallUpdate) {
        if let title = update.title { self.title = title }
        if let name = update.name { self.name = name }
        if let kind = update.kind { self.kind = kind }
        if let status = update.status { self.status = self.status.reporting(status) }
        if let content = update.content { self.content = content }
        if let locations = update.locations { self.locations = locations }
        if let rawInput = update.rawInput { self.rawInput = rawInput }
        if let rawOutput = update.rawOutput { self.rawOutput = rawOutput }
        if let update = update.meta {
            let meta = appendingTerminalOutput(update)
            self.meta = self.meta?.merging(meta) ?? meta
        }
        // ACP v1 has no status for a run that a stop cut short; Claude Code reports one as failed.
        if self.status == .failed, wasCutShort { self.status = .cancelled }
    }
}

public struct PendingPermission: Hashable, Sendable {
    public var requestID: RequestID
    public var options: [PermissionOption]
}
