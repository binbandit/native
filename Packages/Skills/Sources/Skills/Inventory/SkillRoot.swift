import Foundation

/// Where a skill comes from, as the user thinks of it.
public enum SkillScope: Hashable, Sendable {
    /// The user's own skills, in every project.
    case user
    /// One project's skills, checked in with it.
    case project(URL)
    /// Synced from the user's account on the agent's website (Claude's claude.ai skills).
    case account
    /// Shipped with the agent itself.
    case system
    /// From one of the agent's own plugins, by plugin name.
    case plugin(String)

    public var displayName: String {
        switch self {
        case .user: "User"
        case .project: "Project"
        case .account: "Account"
        case .system: "Built in"
        case .plugin(let name): name
        }
    }

    /// Whether Native may install into, update or remove from it: the agent manages the others.
    public var isUserManaged: Bool {
        switch self {
        case .user, .project: true
        case .account, .system, .plugin: false
        }
    }

    public var project: URL? {
        if case .project(let url) = self { url } else { nil }
    }

    /// Which comes first when the same skill is in several places: the user's view of where it
    /// "lives", not any one agent's precedence.
    var rank: Int {
        switch self {
        case .project: 0
        case .user: 1
        case .account: 2
        case .plugin: 3
        case .system: 4
        }
    }
}

/// A folder agents look in for skills, and which agents look there.
public struct SkillRoot: Hashable, Sendable {
    public var path: String
    public var scope: SkillScope
    public var agents: Set<SkillAgentFormat>
    /// How many folders down skills are: 1 for `skills/<name>/SKILL.md`, 2 where an agent groups
    /// them (Claude's synced skills are `synced/<account>/<name>/SKILL.md`).
    var depth = 1

    public init(path: String, scope: SkillScope, agents: Set<SkillAgentFormat>, depth: Int = 1) {
        self.path = path
        self.scope = scope
        self.agents = agents
        self.depth = depth
    }

    /// Roots with the same path and scope as one, read by every agent that reads any of them.
    static func merged(_ roots: [SkillRoot]) -> [SkillRoot] {
        var merged: [SkillRoot] = []
        for root in roots {
            if let index = merged.firstIndex(where: { $0.path == root.path && $0.scope == root.scope }) {
                merged[index].agents.formUnion(root.agents)
            } else {
                merged.append(root)
            }
        }
        return merged
    }
}
