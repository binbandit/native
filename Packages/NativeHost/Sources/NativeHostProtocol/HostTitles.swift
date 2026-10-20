import Foundation

// Titles (docs/durability.md, "Titles"): the host names each task from its first message and keeps
// the user's renames, so a task started with every client closed still gets its title. Every
// `HostSessionSummary` carries the session's titles, so `_native/session/changed` is how clients
// hear about a new or changed one.
extension HostProtocol.Method {
    /// Client → host: who writes titles and with which of the user's instructions
    /// (`ConfigureTitlesParams`). Kept in the host's store, so it holds with no client attached.
    /// Local clients only, like `_native/agents/sync`.
    public static let configureTitles = "_native/titles/configure"
    /// Client → host: the user's own title (or clearing it, for undo), or a title a client wrote
    /// because the host asked for one (`SetSessionTitleParams`).
    public static let setSessionTitle = "_native/session/set_title"
}

/// Who writes a task's title from its first message.
public enum HostTitleProvider: String, Codable, Hashable, Sendable {
    /// The host's on-device model, so titles come with no client attached. Where the host has no
    /// model (Apple Intelligence off, another platform), it asks clients instead, as for `client`.
    case onDevice = "on-device"
    /// A titler that runs only in clients: the host keeps the first message in the session's
    /// `HostSessionTitles.request` until a client with that titler writes the title.
    case client
    /// No generated titles (the user turned titles off): agents' own titles and the user's show.
    case off
    case unknown

    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// The user's own instructions for titles (Settings ▸ AI Instructions), as the host applies them to
/// each session's folder: the organization's while it manages them, else the project's own, else
/// the global ones.
public struct HostTitleInstructions: Codable, Hashable, Sendable {
    public var global: String?
    /// Projects' own, by `AIInstructionProject.key(for:)` of the project folder. An empty text
    /// means none for that project.
    public var projects: [String: String]
    /// The organization's, while it manages instructions; then nothing else counts. An empty text
    /// means it manages them and gives none.
    public var managed: String?

    public init(global: String? = nil, projects: [String: String] = [:], managed: String? = nil) {
        self.global = global
        self.projects = projects
        self.managed = managed
    }
}

public struct ConfigureTitlesParams: Codable, Hashable, Sendable {
    public var provider: HostTitleProvider
    public var instructions: HostTitleInstructions

    public init(provider: HostTitleProvider, instructions: HostTitleInstructions = HostTitleInstructions()) {
        self.provider = provider
        self.instructions = instructions
    }
}

public struct SetSessionTitleParams: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable {
        /// The user's own: it always wins, and nil or empty goes back to the automatic title.
        case user
        /// One a client wrote for `HostSessionTitles.request`. The first generated title stays.
        case generated
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var sessionID: HostSessionID
    public var title: String?
    public var source: Source

    public init(sessionID: HostSessionID, title: String?, source: Source) {
        self.sessionID = sessionID
        self.title = title
        self.source = source
    }
}

/// A session's titles as the host keeps them. A client shows the user's, then the generated one,
/// then the agent's (`HostSessionSummary.title`), then `fallback`.
public struct HostSessionTitles: Codable, Hashable, Sendable {
    public var user: String?
    public var generated: String?
    /// The first message, shortened, while no model will write a title soon: none can run on the
    /// host, or it failed. Never shown over the agent's own title.
    public var fallback: String?
    /// Set while the host wants a client to write the title (`HostTitleProvider.client`, or no
    /// model on the host): what to write it from. A client with a titler answers with
    /// `_native/session/set_title` and source `generated`.
    public var request: HostTitleRequest?

    public init(
        user: String? = nil, generated: String? = nil, fallback: String? = nil, request: HostTitleRequest? = nil
    ) {
        self.user = user
        self.generated = generated
        self.fallback = fallback
        self.request = request
    }
}

/// A title to write: the task's first message and the project it runs in. The client adds the
/// user's instructions for that folder.
public struct HostTitleRequest: Codable, Hashable, Sendable {
    public var projectName: String
    public var prompt: String

    public init(projectName: String, prompt: String) {
        self.projectName = projectName
        self.prompt = prompt
    }
}
