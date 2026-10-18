import Foundation

/// Who said a piece of indexed text, which is also what the role filter picks from.
public enum SearchRole: String, Hashable, Sendable, Codable, CaseIterable {
    /// The user's prompts.
    case user
    /// The agent's replies.
    case agent
    /// The agent's reasoning. Left out of results unless asked for.
    case thought
    /// A tool call: its title, input (paths, commands) and the start and end of its output.
    case tool
    /// The agent's plan.
    case plan
    /// The task's title and project, so a task is found by its name too.
    case title
}

/// Where a hit sits in its transcript, so opening it scrolls to the exact message.
///
/// Message ids aren't stable across a reload (the reducer makes new ones each time a transcript is
/// replayed), so a message is found again by how its text starts. Tool calls keep the agent's id.
public enum SearchAnchor: Hashable, Sendable, Codable {
    /// A tool call, by the agent's id for it.
    case toolCall(id: String)
    /// A transcript item whose id survives a reload (an inter-session message).
    case item(id: String)
    /// A message, by the first characters of its text with whitespace collapsed.
    case message(probe: String)
    /// The task as a whole (its title, project or plan): opens it where it left off.
    case session

    /// How many characters of a message identify it.
    static let probeLength = 80

    /// The probe for a message whose text is `text`.
    public static func message(startingWith text: String) -> SearchAnchor {
        .message(probe: String(SearchText.collapsingWhitespace(text).prefix(probeLength)))
    }

    var stored: String {
        switch self {
        case .toolCall(let id): "tool:" + id
        case .item(let id): "item:" + id
        case .message(let probe): "message:" + probe
        case .session: ""
        }
    }

    init(stored: String) {
        let (kind, value) =
            if let colon = stored.firstIndex(of: ":") {
                (stored[..<colon], String(stored[stored.index(after: colon)...]))
            } else {
                (Substring(), "")
            }
        switch kind {
        case "tool": self = .toolCall(id: value)
        case "item": self = .item(id: value)
        case "message": self = .message(probe: value)
        default: self = .session
        }
    }
}

/// One searchable piece of a transcript: a message, a tool call or the plan.
public struct SearchDocument: Hashable, Sendable {
    public var role: SearchRole
    public var text: String
    public var anchor: SearchAnchor
    public var date: Date?
    /// Whether the piece changed files, for the "has diff" filter.
    public var hasDiff: Bool

    public init(role: SearchRole, text: String, anchor: SearchAnchor, date: Date? = nil, hasDiff: Bool = false) {
        self.role = role
        self.text = text
        self.anchor = anchor
        self.date = date
        self.hasDiff = hasDiff
    }
}

/// Identifies a session across agents, whose session ids can collide.
public struct SearchSessionKey: Hashable, Sendable, Codable {
    /// The agent's id in Native (`claude-code`, `codex`, or whatever a plugin calls it).
    public var agent: String
    /// The agent's id for the session.
    public var session: String

    public init(agent: String, session: String) {
        self.agent = agent
        self.session = session
    }
}

/// What the index knows about a session besides its text.
public struct SearchSessionRecord: Hashable, Sendable, Codable {
    public var key: SearchSessionKey
    public var title: String?
    /// The folder the session ran in.
    public var cwd: String
    /// The project the session belongs to, for grouping and the project filter: a Native project's
    /// folder, or the session's own folder when no project claims it.
    public var project: String
    public var createdAt: Date?
    public var updatedAt: Date?
    public var isArchived: Bool

    public init(
        key: SearchSessionKey, title: String? = nil, cwd: String, project: String? = nil, createdAt: Date? = nil,
        updatedAt: Date? = nil, isArchived: Bool = false
    ) {
        self.key = key
        self.title = title
        self.cwd = cwd
        self.project = project ?? cwd
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    /// The project's folder name, as the sidebar shows it.
    public var projectName: String {
        URL(filePath: project).lastPathComponent
    }
}
