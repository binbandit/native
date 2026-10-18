import Foundation

/// What Native asks Codex to leave out of every session, as the `CODEX_CONFIG` JSON its ACP adapter
/// (codex-acp 2.2.2) merges into each session's config. Every feature adds to one value, so MCP
/// servers and skills always land in the same document.
///
/// Known limit: when a session brings MCP servers of its own (Native's orchestration server, say),
/// the adapter replaces the whole `mcp_servers` table with them, and the dotted
/// `mcp_servers.<name>.enabled` keys only win when they happen to apply after it.
/// docs/agent-session-overrides.md has the details and the adapter change that fixes it.
public struct CodexConfigOverrides: Hashable, Sendable {
    /// MCP servers by the name Codex gives them, and only those its own config defines: any other
    /// name becomes an entry with no command, and Codex then fails every new session ("Internal
    /// error"). `MCPLibrary.launchPolicy` names only an agent's configured servers for this reason.
    public var disabledMCPServers: Set<String>
    /// Skills by the path of their SKILL.md.
    public private(set) var disabledSkillFiles: Set<String>
    /// How long Codex keeps a session nothing listens to any more (after `session/close`) before
    /// unloading it, and the MCP servers it started for it with it (`thread_unload_delay_secs`).
    /// Unset, Codex holds them for a long while: often hundreds of megabytes per closed session.
    public var threadUnloadDelay: Duration?

    public init(
        disabledMCPServers: Set<String> = [], disabledSkills: some Sequence<String> = [String](),
        threadUnloadDelay: Duration? = nil
    ) {
        self.disabledMCPServers = disabledMCPServers
        self.disabledSkillFiles = []
        self.threadUnloadDelay = threadUnloadDelay
        disabledSkills.forEach { disableSkill(at: $0) }
    }

    /// A skill by its folder or its SKILL.md; Codex matches `skills.config` entries by the file.
    public mutating func disableSkill(at path: String) {
        disabledSkillFiles.insert(path.hasSuffix("/SKILL.md") ? path : path + "/SKILL.md")
    }

    public var isEmpty: Bool {
        disabledMCPServers.isEmpty && disabledSkillFiles.isEmpty && threadUnloadDelay == nil
    }

    /// The document. Servers are switched off twice: the nested table holds once the adapter merges
    /// a session's servers into it, and the dotted keys cover today's adapter as far as it allows.
    public var config: JSONValue {
        var config: [String: JSONValue] = [:]
        let servers = disabledMCPServers.sorted()
        if !servers.isEmpty {
            let off = JSONValue.object(["enabled": .bool(false)])
            config["mcp_servers"] = .object(Dictionary(uniqueKeysWithValues: servers.map { ($0, off) }))
            for server in servers { config["mcp_servers.\(server).enabled"] = .bool(false) }
        }
        if let threadUnloadDelay {
            config["thread_unload_delay_secs"] = .number(Double(threadUnloadDelay.components.seconds))
        }
        let skills = disabledSkillFiles.sorted()
        if !skills.isEmpty {
            // Hidden from the model; the adapter's `$skill` command list still shows them, since it
            // builds that from `skills/list` (verified with gpt-6.1-sol).
            let entries = skills.map { JSONValue.object(["path": .string($0), "enabled": .bool(false)]) }
            config["skills"] = .object(["config": .array(entries)])
        }
        return .object(config)
    }

    /// The agent process's environment for these overrides; empty when there are none.
    public var environment: [String: String] {
        guard !isEmpty else { return [:] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return [:] }
        return ["CODEX_CONFIG": String(decoding: data, as: UTF8.self)]
    }
}
