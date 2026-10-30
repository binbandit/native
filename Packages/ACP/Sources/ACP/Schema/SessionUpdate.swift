import Foundation

/// The params of a `session/update` notification.
public struct SessionNotification: Decodable, Sendable {
    public var sessionId: SessionID
    public var update: SessionUpdate
}

public enum SessionUpdate: Sendable {
    case userMessageChunk(ContentChunk)
    case agentMessageChunk(ContentChunk)
    case agentThoughtChunk(ContentChunk)
    case toolCall(ToolCallUpdate)
    case toolCallUpdate(ToolCallUpdate)
    case plan([PlanEntry])
    case availableCommands([AvailableCommand])
    case configOptions([ConfigOption])
    case sessionInfo(title: String?)
    case usage(Usage)
    case compaction(CompactionUpdate)
    case compactionSummary(CompactionSummaryChunk)
    /// The agent switched its own mode (sent by agents that don't report it as a config option).
    case currentMode(String)
    case subagent(SubagentUpdate)
    case sessionMessage(SessionMessageUpdate)
    case sessionMessageChunk(SessionMessageChunk)
    /// An update kind Native doesn't handle yet; safe to ignore.
    case unsupported(String)
}

extension SessionUpdate: Decodable {
    private enum CodingKeys: String, CodingKey {
        case sessionUpdate, entries, availableCommands, configOptions, title, currentModeId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .sessionUpdate)
        // Each variant's fields sit beside the `sessionUpdate` discriminator, so payload types decode
        // from the same decoder.
        self =
            switch kind {
            case "user_message_chunk": .userMessageChunk(try ContentChunk(from: decoder))
            case "agent_message_chunk": .agentMessageChunk(try ContentChunk(from: decoder))
            case "agent_thought_chunk": .agentThoughtChunk(try ContentChunk(from: decoder))
            case "tool_call": .toolCall(try ToolCallUpdate(from: decoder))
            case "tool_call_update": .toolCallUpdate(try ToolCallUpdate(from: decoder))
            case "plan": .plan(try container.decode([PlanEntry].self, forKey: .entries))
            case "available_commands_update":
                .availableCommands(try container.decode([AvailableCommand].self, forKey: .availableCommands))
            case "config_option_update":
                .configOptions(try container.decode([ConfigOption].self, forKey: .configOptions))
            case "session_info_update": .sessionInfo(title: try container.decodeIfPresent(String.self, forKey: .title))
            case "usage_update": .usage(try Usage(from: decoder))
            case "compaction_update": .compaction(try CompactionUpdate(from: decoder))
            case "compaction_summary_chunk": .compactionSummary(try CompactionSummaryChunk(from: decoder))
            case "current_mode_update": .currentMode(try container.decode(String.self, forKey: .currentModeId))
            case "subagent_update": .subagent(try SubagentUpdate(from: decoder))
            // The subagents RFD's earlier draft, which Cursor still sends.
            case "subagent_spawned": .subagent(try SubagentUpdate(spawned: decoder))
            case "subagent_state_update": .subagent(try SubagentUpdate(stateChange: decoder))
            case "session_message": .sessionMessage(try SessionMessageUpdate(from: decoder))
            case "session_message_chunk": .sessionMessageChunk(try SessionMessageChunk(from: decoder))
            default: .unsupported(kind)
            }
    }
}

public struct ContentChunk: Decodable, Hashable, Sendable {
    public var content: ContentBlock
    /// Chunks sharing an id belong to the same message; agents may omit it.
    public var messageId: String?

    public init(content: ContentBlock, messageId: String? = nil) {
        self.content = content
        self.messageId = messageId
    }
}

public struct PlanEntry: Decodable, Hashable, Sendable {
    public var content: String
    public var priority: String
    public var status: Status

    public enum Status: String, Hashable, Sendable, Decodable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

public struct AvailableCommand: Decodable, Hashable, Sendable {
    public var name: String
    public var description: String

    /// Skills already carry their invocation prefix in the advertised name.
    public var invocation: String {
        name.hasPrefix("$") ? name : "/\(name)"
    }
}

public struct Usage: Decodable, Hashable, Sendable {
    /// Tokens currently in the context window.
    public var used: Int
    /// The context window's size in tokens.
    public var size: Int
    public var cost: Cost?
    /// Agent-specific extras, such as Claude Code's rate-limit status.
    public var _meta = UsageMeta()

    /// The provider's rate-limit status, when this update carried one.
    public var rateLimit: RateLimitInfo? {
        _meta.rateLimit
    }

    /// The model the agent reports running, for agents that offer no model setting to read it from.
    public var model: String? {
        _meta.model
    }

    public struct Cost: Decodable, Hashable, Sendable {
        public var amount: Double
        public var currency: String
    }

    public var fractionUsed: Double {
        size > 0 ? Double(used) / Double(size) : 0
    }
}
