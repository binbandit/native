import Foundation

/// A named way of working for a task: instructions Native gives the agent, and the settings it
/// applies on the way in (an autonomy level, the agent's own plan mode, a model). Modes are built
/// in (`Mode.builtIn`), the user's own, or shared by a project as files (`ModeFile`).
public struct Mode: Identifiable, Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            rawValue = value
        }

        /// A mode the user made, which keeps its id through renames.
        public static func custom(_ uuid: String) -> Self {
            Self(rawValue: "custom.\(uuid)")
        }

        /// A project's mode, named after its file (`.native/modes/security-review.md`).
        public static func project(_ slug: String) -> Self {
            Self(rawValue: "project.\(slug)")
        }
    }

    public enum Source: String, Hashable, Codable, Sendable {
        case builtIn
        /// Made by the user in Settings, for every project.
        case custom
        /// Committed to a project's repository.
        case project
    }

    public var id: ID
    public var name: String
    /// An SF Symbol.
    public var symbol: String
    /// One plain line saying what the mode does, for the picker.
    public var summary: String
    /// What the agent is told, in Markdown. Build has none.
    public var instructions: String
    public var settings: ModeSettings
    public var source: Source

    public init(
        id: ID, name: String, symbol: String, summary: String, instructions: String,
        settings: ModeSettings = ModeSettings(), source: Source
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.summary = summary
        self.instructions = instructions
        self.settings = settings
        self.source = source
    }

    /// How the transcript and the agent name it: "Debug mode".
    public var label: String {
        "\(name) mode"
    }
}

/// The settings a mode applies when it's picked, each optional: an unset one stays as the task has it.
public struct ModeSettings: Hashable, Codable, Sendable {
    /// How much the agent may do without asking.
    public var autonomy: ModeAutonomy?
    /// Switches the agent's own plan mode on; an agent without one is kept read-only instead.
    public var usesPlanMode: Bool
    /// A model, by the agent's value or name for it. Skipped on agents that don't offer it.
    public var model: String?
    /// A reasoning effort, by the agent's value or name. Skipped where it isn't offered.
    public var effort: String?

    public init(autonomy: ModeAutonomy? = nil, usesPlanMode: Bool = false, model: String? = nil, effort: String? = nil)
    {
        self.autonomy = autonomy
        self.usesPlanMode = usesPlanMode
        self.model = model
        self.effort = effort
    }

    public var isEmpty: Bool {
        self == ModeSettings()
    }
}

/// How much an agent may do without asking, in terms that hold across agents. Each maps to the
/// nearest permission mode the agent offers (`ModeResolver`).
public enum ModeAutonomy: String, Codable, CaseIterable, Sendable {
    /// Reads and answers; changes nothing.
    case readOnly = "read-only"
    /// Asks before every edit and command.
    case ask
    /// Edits files in the project on its own, and asks before the rest.
    case edit
    /// Decides for itself, and asks only when something looks risky.
    case auto
    /// Never asks.
    case full

    public var title: String {
        switch self {
        case .readOnly: "Read-only"
        case .ask: "Ask first"
        case .edit: "Edit files"
        case .auto: "Auto"
        case .full: "Full access"
        }
    }

    public var summary: String {
        switch self {
        case .readOnly: "Reads and answers, changes nothing"
        case .ask: "Asks before every edit and command"
        case .edit: "Edits files in the project, asks before the rest"
        case .auto: "Asks only when something looks risky"
        case .full: "Does everything without asking"
        }
    }

    /// Whether a repository's own mode may set it: a project can make the agent more careful,
    /// never give it more freedom than the user chose.
    public var isAllowedInProjects: Bool {
        self == .readOnly || self == .ask
    }
}
