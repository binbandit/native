import Foundation

/// `elicitation/create`: the agent asks the user for structured input. In form mode it sends a JSON
/// Schema of fields to fill in; Claude Code sends its AskUserQuestion tool this way (a select field
/// per question, plus a free-text companion), and Codex forwards MCP servers' forms. Native
/// advertises form mode only.
public struct CreateElicitationRequest: Decodable, Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        case form
        case url
        /// A mode Native doesn't handle yet; answer it with `cancel`.
        case unsupported(String)
    }

    public var sessionId: SessionID
    public var mode: Mode
    /// The tool call the question belongs to, when there is one (AskUserQuestion's).
    public var toolCallId: String?
    public var message: String
    /// The fields to fill in, for form mode.
    public var requestedSchema: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case sessionId, mode, toolCallId, message, requestedSchema
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(SessionID.self, forKey: .sessionId)
        mode =
            switch try container.decode(String.self, forKey: .mode) {
            case "form": .form
            case "url": .url
            case let other: .unsupported(other)
            }
        toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        requestedSchema = try container.decodeIfPresent(JSONValue.self, forKey: .requestedSchema)
    }
}

/// The answer to `elicitation/create`.
public enum CreateElicitationResponse: Encodable, Hashable, Sendable {
    /// The user filled in the form; `content` maps field names to their values.
    case accept(content: [String: JSONValue])
    /// The user chose not to answer. Claude Code tells the model the questions were skipped.
    case decline
    /// The question was dismissed without a choice, as when the turn is cancelled. Claude Code
    /// aborts the tool call.
    case cancel

    private enum CodingKeys: String, CodingKey {
        case action, content
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .accept(let content):
            try container.encode("accept", forKey: .action)
            try container.encode(content, forKey: .content)
        case .decline:
            try container.encode("decline", forKey: .action)
        case .cancel:
            try container.encode("cancel", forKey: .action)
        }
    }
}
