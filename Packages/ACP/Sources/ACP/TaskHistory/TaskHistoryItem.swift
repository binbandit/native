import Foundation

/// One thing that happened in a task, in the provider-neutral form every agent's history shares:
/// a message, a reply, a tool call, a plan, a turn's end. Items are numbered per task without gaps
/// and never change once written.
public struct TaskHistoryItem: Hashable, Sendable, Codable, Identifiable {
    /// The item's place in the task, from 1.
    public var seq: Int
    /// The participant (`TaskHistoryParticipant.ordinal`) whose agent session produced the item or
    /// received it as a prompt.
    public var source: Int
    /// The prompt request that started the item's turn. Nil for history imported from an agent's
    /// replay, which carries no request ids.
    public var turn: UUID?
    /// Nil for imported history, which agents replay without times.
    public var at: Date?
    public var body: Body

    public init(seq: Int, source: Int, turn: UUID? = nil, at: Date? = nil, body: Body) {
        self.seq = seq
        self.source = source
        self.turn = turn
        self.at = at
        self.body = body
    }

    public var id: Int { seq }
}

extension TaskHistoryItem {
    public enum Body: Hashable, Sendable {
        case user(Message)
        case agent(String)
        case thought(String)
        case tool(Tool)
        case plan([PlanStep])
        case turnEnded(stopReason: String)
        /// A kind a newer host wrote. It keeps its place in the order and is otherwise skipped.
        case unknown(kind: String)
    }

    /// A message to the agent: the user's, or one Native's tools or queue sent on their behalf.
    public struct Message: Hashable, Sendable, Codable {
        public var text: String
        /// The names of the files and images that went with it; their contents stay where they were.
        public var attachments: [String]
        /// `PromptEcho.Origin`'s raw value: `user`, `queued`, `task` or `recovery`.
        public var origin: String
        /// Sent into a turn that was already running.
        public var steered: Bool

        public init(text: String, attachments: [String] = [], origin: String = "user", steered: Bool = false) {
            self.text = text
            self.attachments = attachments
            self.origin = origin
            self.steered = steered
        }
    }

    /// What a tool call did, without its full output.
    public struct Tool: Hashable, Sendable, Codable {
        public var id: String
        public var title: String
        /// ACP's tool kind (`read`, `edit`, `execute`…).
        public var kind: String
        /// ACP's status (`completed`, `failed`…), or how Native settled a call the agent never finished.
        public var status: String
        public var paths: [String]
        /// The command or the input that says what the call did, shortened.
        public var input: String?
        /// The start of what it returned or printed.
        public var output: String?

        public init(
            id: String, title: String, kind: String, status: String, paths: [String] = [], input: String? = nil,
            output: String? = nil
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.status = status
            self.paths = paths
            self.input = input
            self.output = output
        }
    }

    public struct PlanStep: Hashable, Sendable, Codable {
        public var content: String
        /// ACP's plan entry status: `pending`, `in_progress` or `completed`.
        public var status: String

        public init(content: String, status: String) {
            self.content = content
            self.status = status
        }
    }
}

extension TaskHistoryItem.Body: Codable {
    /// How the store and the wire name each kind; the store also keeps it in its own column.
    public var kind: String {
        switch self {
        case .user: "user"
        case .agent: "agent"
        case .thought: "thought"
        case .tool: "tool"
        case .plan: "plan"
        case .turnEnded: "turn_ended"
        case .unknown(let kind): kind
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, message, text, tool, plan, stopReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "user": self = .user(try container.decode(TaskHistoryItem.Message.self, forKey: .message))
        case "agent": self = .agent(try container.decode(String.self, forKey: .text))
        case "thought": self = .thought(try container.decode(String.self, forKey: .text))
        case "tool": self = .tool(try container.decode(TaskHistoryItem.Tool.self, forKey: .tool))
        case "plan": self = .plan(try container.decode([TaskHistoryItem.PlanStep].self, forKey: .plan))
        case "turn_ended": self = .turnEnded(stopReason: try container.decode(String.self, forKey: .stopReason))
        default: self = .unknown(kind: kind)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .user(let message): try container.encode(message, forKey: .message)
        case .agent(let text), .thought(let text): try container.encode(text, forKey: .text)
        case .tool(let tool): try container.encode(tool, forKey: .tool)
        case .plan(let steps): try container.encode(steps, forKey: .plan)
        case .turnEnded(let stopReason): try container.encode(stopReason, forKey: .stopReason)
        case .unknown: break
        }
    }
}
