import ACP
import Foundation

/// What plugins want left out of the sessions Native starts, as intent rather than mechanism:
/// features say which MCP servers or skills to turn off, and each agent's plugin translates that
/// into its own mechanism (`SessionPolicyTranslator`). Nothing here edits an agent's files.
struct SessionPolicy: Hashable, Sendable {
    /// How far an intent reaches.
    enum Scope: Hashable, Sendable {
        /// Every session of the agent, in every project. Agents that can only apply intents when
        /// they launch can apply these.
        case allProjects
        /// Only the session it was asked for (its project).
        case session
    }

    /// An MCP server the agent loads from its own configuration, by the name it gives it.
    struct DisabledMCPServer: Hashable, Sendable {
        var name: String
        var scope: Scope
    }

    /// A skill, by name or by the path of its folder.
    struct DisabledSkill: Hashable, Sendable {
        var name: String?
        var path: String?
        var scope: Scope
    }

    var disabledMCPServers: [DisabledMCPServer] = []
    var disabledSkills: [DisabledSkill] = []

    static let none = SessionPolicy()

    var isEmpty: Bool {
        disabledMCPServers.isEmpty && disabledSkills.isEmpty
    }

    /// Everything both policies ask for.
    func merging(_ other: SessionPolicy) -> SessionPolicy {
        SessionPolicy(
            disabledMCPServers: disabledMCPServers
                + other.disabledMCPServers.filter { !disabledMCPServers.contains($0) },
            disabledSkills: disabledSkills + other.disabledSkills.filter { !disabledSkills.contains($0) }
        )
    }

    /// The intents that reach every session, for agents that apply them at launch.
    var allProjectsOnly: SessionPolicy {
        SessionPolicy(
            disabledMCPServers: disabledMCPServers.filter { $0.scope == .allProjects },
            disabledSkills: disabledSkills.filter { $0.scope == .allProjects }
        )
    }
}

/// An agent's own way of applying a `SessionPolicy`. Lives with the agent's plugin, since only it
/// knows its adapter. docs/agent-session-overrides.md records what each built-in agent supports and
/// how it was verified.
protocol SessionPolicyTranslator: Sendable {
    /// What goes into the `_meta` of `session/new` and `session/load` for one session.
    func sessionMeta(for policy: SessionPolicy) -> [String: JSONValue]
    /// Environment for the agent's process, from the intents that reach every session. Applies
    /// when the agent (re)starts.
    func launchEnvironment(for policy: SessionPolicy) -> [String: String]
    /// How the agent can apply each kind of intent, for the UI to say.
    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport
}

/// How an agent can apply a kind of intent.
enum SessionPolicySupport: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case mcpServers, skills
    }

    /// For each session, per project.
    case perSession
    /// For all of the agent's sessions at once, when it launches; with a caveat for the user when
    /// it doesn't always hold.
    case atLaunch(caveat: String?)
    /// Not at all; the reason is for the user.
    case unsupported(String)
}

extension SessionPolicyTranslator {
    func sessionMeta(for policy: SessionPolicy) -> [String: JSONValue] { [:] }
    func launchEnvironment(for policy: SessionPolicy) -> [String: String] { [:] }
}
