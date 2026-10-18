import Foundation

/// Where an agent keeps skills and how far Native can turn one off for it. An agent plugin names
/// its format, the way it names its MCP configuration format. The paths come from each agent's
/// docs and binaries; docs/skills.md records which were verified and how.
public enum SkillAgentFormat: String, CaseIterable, Hashable, Sendable, Codable {
    case claudeCode = "claude-code"
    case codex
    case cursor
    case openCode = "opencode"
    case pi
    case copilot

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .openCode: "OpenCode"
        case .pi: "Pi"
        case .copilot: "Copilot"
        }
    }

    /// How a skill can be left out of this agent's sessions without touching its files.
    public var switching: SkillSwitching {
        switch self {
        case .claudeCode: .perSession
        case .codex: .perProcess
        case .cursor, .openCode, .pi, .copilot: .unsupported
        }
    }

    /// Whether a switch reaches skills from `scope` at all for this agent.
    public func canSwitch(_ scope: SkillScope) -> Bool {
        switch (self.switching, scope) {
        case (.unsupported, _): false
        // Claude Code's `skillOverrides` doesn't reach plugin-qualified skills (verified).
        case (_, .plugin) where self == .claudeCode: false
        default: true
        }
    }

    /// The folders this agent reads, most specific first: each project's, then the user's, then
    /// what ships with the agent. Claude Code's plugin skills come from `ClaudePlugins`.
    public func roots(home: String, environment: [String: String], projects: [URL]) -> [SkillRoot] {
        let user = userDirectories(home: home, environment: environment).map {
            SkillRoot(path: $0, scope: .user, agents: [self])
        }
        let project = projects.flatMap { url in
            projectDirectories.map {
                SkillRoot(path: SkillPaths.join(SkillPaths.key(url), $0), scope: .project(url), agents: [self])
            }
        }
        var extra: [SkillRoot] = []
        switch self {
        case .claudeCode:
            extra.append(
                SkillRoot(
                    path: SkillPaths.join(claudeHome(home: home, environment: environment), "skills", "synced"),
                    scope: .account, agents: [self], depth: 2))
        case .codex:
            extra.append(
                SkillRoot(
                    path: SkillPaths.join(codexHome(home: home, environment: environment), "skills", ".system"),
                    scope: .system, agents: [self]))
        default: break
        }
        return project + user + extra
    }

    /// Project-relative skill folders.
    var projectDirectories: [String] {
        switch self {
        case .claudeCode: [".claude/skills"]
        case .codex: [".agents/skills"]
        case .cursor: [".cursor/skills", ".claude/skills", ".codex/skills"]
        case .openCode: [".opencode/skills", ".opencode/skill", ".claude/skills", ".agents/skills"]
        case .pi: [".pi/skills", ".agents/skills"]
        case .copilot: [".github/skills", ".claude/skills", ".agents/skills"]
        }
    }

    func userDirectories(home: String, environment: [String: String]) -> [String] {
        let claude = SkillPaths.join(claudeHome(home: home, environment: environment), "skills")
        let agents = SkillPaths.join(home, ".agents", "skills")
        switch self {
        case .claudeCode:
            return [claude]
        case .codex:
            return [SkillPaths.join(codexHome(home: home, environment: environment), "skills"), agents]
        case .cursor:
            return [SkillPaths.join(home, ".cursor", "skills"), claude, SkillPaths.join(home, ".codex", "skills")]
        case .openCode:
            let config = environment["XDG_CONFIG_HOME"] ?? SkillPaths.join(home, ".config")
            return [
                SkillPaths.join(config, "opencode", "skills"), SkillPaths.join(config, "opencode", "skill"), claude,
                agents,
            ]
        case .pi:
            let agentDirectory = environment["PI_CODING_AGENT_DIR"] ?? SkillPaths.join(home, ".pi", "agent")
            return [SkillPaths.join(agentDirectory, "skills"), agents]
        case .copilot:
            return [SkillPaths.join(home, ".copilot", "skills"), claude, agents]
        }
    }

    /// Where Native installs a skill for this agent alone: its own folder.
    func installDirectory(for scope: SkillInstallScope, home: String, environment: [String: String]) -> String {
        switch scope {
        case .user: userDirectories(home: home, environment: environment)[0]
        case .project(let url): SkillPaths.join(SkillPaths.key(url), projectDirectories[0])
        }
    }

    /// Whether this agent reads skills from `directory` (a user or project skills folder).
    func reads(_ directory: String, home: String, environment: [String: String], project: URL?) -> Bool {
        roots(home: home, environment: environment, projects: project.map { [$0] } ?? []).contains {
            $0.path == directory
        }
    }

    private func claudeHome(home: String, environment: [String: String]) -> String {
        environment["CLAUDE_CONFIG_DIR"] ?? SkillPaths.join(home, ".claude")
    }

    private func codexHome(home: String, environment: [String: String]) -> String {
        environment["CODEX_HOME"] ?? SkillPaths.join(home, ".codex")
    }
}

/// How an agent can leave a skill out of a session without its files changing.
public enum SkillSwitching: Hashable, Sendable {
    /// Per session, as it starts (Claude Code: the session's `skillOverrides` setting).
    case perSession
    /// For the agent's whole process, so a change applies once it restarts, and only by file
    /// (Codex: `skills.config` in its launch configuration).
    case perProcess
    /// No way short of editing or moving its files, which Native doesn't do.
    case unsupported
}

/// Where a new skill goes.
public enum SkillInstallScope: Hashable, Sendable {
    case user
    case project(URL)
}
