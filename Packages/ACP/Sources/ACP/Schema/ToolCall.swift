import Foundation

public enum ToolKind: String, Hashable, Sendable, Decodable {
    case read, edit, delete, move, search, execute, think, fetch
    case switchMode = "switch_mode"
    case other

    public init(from decoder: any Decoder) throws {
        self = ToolKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
}

public enum ToolCallStatus: Hashable, Sendable, Decodable {
    case pending
    case inProgress
    case completed
    case failed
    /// Never sent by ACP v1 agents: clients mark calls that were still open when a turn was cancelled.
    case cancelled

    public init(from decoder: any Decoder) throws {
        self = switch try decoder.singleValueContainer().decode(String.self) {
        case "in_progress": .inProgress
        case "completed": .completed
        case "failed": .failed
        default: .pending
        }
    }

    public var isFinished: Bool {
        switch self {
        case .pending, .inProgress: false
        case .completed, .failed, .cancelled: true
        }
    }
}

public struct ToolCallLocation: Decodable, Hashable, Sendable {
    public var path: String
    public var line: Int?
}

public struct FileDiff: Hashable, Sendable {
    public var path: String
    /// `nil` when the tool creates the file.
    public var oldText: String?
    public var newText: String

    /// For diffs a client computes itself, such as a file's uncommitted changes.
    public init(path: String, oldText: String?, newText: String) {
        self.path = path
        self.oldText = oldText
        self.newText = newText
    }
}

public enum ToolCallContent: Hashable, Sendable, Decodable {
    case content(ContentBlock)
    case diff(FileDiff)
    case terminal(id: String)
    case unsupported(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, content, path, oldText, newText, terminalId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "content":
            self = .content(try container.decode(ContentBlock.self, forKey: .content))
        case "diff":
            self = .diff(FileDiff(
                path: try container.decode(String.self, forKey: .path),
                oldText: try container.decodeIfPresent(String.self, forKey: .oldText),
                newText: try container.decode(String.self, forKey: .newText)
            ))
        case "terminal":
            self = .terminal(id: try container.decode(String.self, forKey: .terminalId))
        default:
            self = .unsupported(type: type)
        }
    }
}

/// The fields of a `tool_call` or `tool_call_update`. Updates only carry what changed, so everything
/// but the id is optional; a present field replaces the previous value.
public struct ToolCallUpdate: Decodable, Hashable, Sendable {
    public var toolCallId: String
    public var title: String?
    public var name: String?
    public var kind: ToolKind?
    public var status: ToolCallStatus?
    public var content: [ToolCallContent]?
    public var locations: [ToolCallLocation]?
    public var rawInput: JSONValue?
    public var rawOutput: JSONValue?
    /// The agent's own extra data (`_meta`), such as Claude Code's `toolResponse`.
    public var meta: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case toolCallId, title, name, kind, status, content, locations, rawInput, rawOutput
        case meta = "_meta"
    }

    public init(toolCallId: String, title: String? = nil, kind: ToolKind? = nil, status: ToolCallStatus? = nil) {
        self.toolCallId = toolCallId
        self.title = title
        self.kind = kind
        self.status = status
    }
}

// MARK: - Permissions

/// Sent by the agent before running a tool that needs the user's approval.
public struct RequestPermissionRequest: Decodable, Sendable {
    public var sessionId: SessionID
    public var toolCall: ToolCallUpdate
    public var options: [PermissionOption]
}

public struct PermissionOption: Decodable, Hashable, Sendable, Identifiable {
    public var optionId: String
    public var name: String
    public var kind: Kind

    public enum Kind: String, Hashable, Sendable, Decodable {
        case allowOnce = "allow_once"
        case allowAlways = "allow_always"
        case rejectOnce = "reject_once"
        case rejectAlways = "reject_always"
    }

    public var id: String { optionId }

    public var isRejection: Bool { kind == .rejectOnce || kind == .rejectAlways }
}

public enum RequestPermissionResponse: Encodable, Sendable {
    case selected(optionId: String)
    case cancelled

    private enum CodingKeys: String, CodingKey {
        case outcome, optionId
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var outcome = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .outcome)
        switch self {
        case .selected(let optionId):
            try outcome.encode("selected", forKey: .outcome)
            try outcome.encode(optionId, forKey: .optionId)
        case .cancelled:
            try outcome.encode("cancelled", forKey: .outcome)
        }
    }
}
