import Foundation

/// Encodes task and message prompt framing because the prompt is the only channel that identifies
/// a sender and reply path; transcripts parse it back to show that sender rather than its header.
public struct TaskPromptFrame: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case task
        case message
    }

    public enum Sender: Hashable, Sendable {
        case parent(agent: String)
        case task(id: String, label: String)
        case sibling(id: String, label: String)
    }

    public let kind: Kind
    public let sender: Sender
    public let body: String

    public init?(parsing text: String) {
        guard let terminator = text.range(of: Self.headerTerminator) else { return nil }
        let header = String(text[..<terminator.lowerBound])
        let body = String(text[terminator.upperBound...])

        if header.hasPrefix(Self.taskHeaderPrefix), header.hasSuffix(Self.taskHeaderSuffix) {
            let agentStart = header.index(header.startIndex, offsetBy: Self.taskHeaderPrefix.count)
            let agentEnd = header.index(header.endIndex, offsetBy: -Self.taskHeaderSuffix.count)
            let agent = String(header[agentStart..<agentEnd])
            guard !agent.isEmpty else { return nil }
            kind = .task
            sender = .parent(agent: agent)
            self.body = body
            return
        }

        guard header.hasPrefix(Self.messageHeaderPrefix), header.hasSuffix(Self.messageHeaderSuffix) else { return nil }
        let contentStart = header.index(header.startIndex, offsetBy: Self.messageHeaderPrefix.count)
        let contentEnd = header.index(header.endIndex, offsetBy: -Self.messageHeaderSuffix.count)
        let content = String(header[contentStart..<contentEnd])
        guard let divider = content.range(of: Self.messageReplyPrefix, options: .backwards) else { return nil }

        let senderPhrase = String(content[..<divider.lowerBound])
        let replyStart = divider.upperBound
        let replyTo = String(content[replyStart...])
        guard let sender = Self.parseSender(senderPhrase, replyTo: replyTo) else { return nil }
        kind = .message
        self.sender = sender
        self.body = body
    }

    public static func task(_ body: String, fromParent agent: String) -> String {
        taskHeaderPrefix + agent + taskHeaderSuffix + headerTerminator + body
    }

    public static func message(_ body: String, from sender: Sender) -> String {
        let senderPhrase: String
        let replyTo: String
        switch sender {
        case let .parent(agent):
            senderPhrase = parentSenderPrefix + agent + parentSenderSuffix
            replyTo = "parent"
        case let .task(id, label):
            senderPhrase = taskSenderPrefix + label
            replyTo = id
        case let .sibling(id, label):
            senderPhrase = siblingSenderPrefix + label
            replyTo = id
        }
        return messageHeaderPrefix + senderPhrase + messageReplyPrefix + replyTo + messageHeaderSuffix
            + headerTerminator + body
    }

    private static func parseSender(_ phrase: String, replyTo: String) -> Sender? {
        if phrase.hasPrefix(parentSenderPrefix), phrase.hasSuffix(parentSenderSuffix), replyTo == "parent" {
            let agentStart = phrase.index(phrase.startIndex, offsetBy: parentSenderPrefix.count)
            let agentEnd = phrase.index(phrase.endIndex, offsetBy: -parentSenderSuffix.count)
            return .parent(agent: String(phrase[agentStart..<agentEnd]))
        }

        if phrase.hasPrefix(taskSenderPrefix) {
            let label = String(phrase.dropFirst(taskSenderPrefix.count))
            guard taskID(in: label) == replyTo, !replyTo.isEmpty else { return nil }
            return .task(id: replyTo, label: label)
        }

        if phrase.hasPrefix(siblingSenderPrefix) {
            let label = String(phrase.dropFirst(siblingSenderPrefix.count))
            guard taskID(in: label) == replyTo, !replyTo.isEmpty else { return nil }
            return .sibling(id: replyTo, label: label)
        }

        return nil
    }

    private static func taskID(in label: String) -> String? {
        guard let separator = label.range(of: " ("), separator.lowerBound != label.startIndex else { return nil }
        return String(label[..<separator.lowerBound])
    }

    private static let headerTerminator = "]\n\n"
    private static let taskHeaderPrefix = "[A task from your parent session ("
    private static let taskHeaderSuffix =
        "), handed to you through Native. What you say at the end of your turn goes back to it as your reply. To message it or its other tasks while you work, use the native MCP tools list_tasks and send_message."
    private static let messageHeaderPrefix = "[Message from "
    private static let messageReplyPrefix = ". To reply, call send_message with to: \""
    private static let messageHeaderSuffix = "\"."
    private static let parentSenderPrefix = "your parent session ("
    private static let parentSenderSuffix = ")"
    private static let taskSenderPrefix = "your task "
    private static let siblingSenderPrefix = "sibling task "
}
