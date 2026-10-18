import Foundation

/// Settings Native lays over one Claude Code session, as the `_meta.claudeCode.options.settings`
/// of `session/new` and `session/load`. Its ACP adapter (claude-agent-acp 0.93.0) hands them to the
/// Agent SDK, whose programmatic tier merges them with the user's own settings: a denied MCP server
/// isn't started, and a skill set to "off" is hidden from the model and the slash commands
/// (plugin-qualified skills excepted). The user's files are untouched.
public struct ClaudeCodeSessionSettings: Hashable, Sendable {
    /// MCP servers by the name Claude Code gives them.
    public var deniedMCPServers: Set<String>
    /// Skills by name.
    public var disabledSkills: Set<String>

    public init(deniedMCPServers: Set<String> = [], disabledSkills: Set<String> = []) {
        self.deniedMCPServers = deniedMCPServers
        self.disabledSkills = disabledSkills
    }

    public var isEmpty: Bool {
        deniedMCPServers.isEmpty && disabledSkills.isEmpty
    }

    /// The request's `_meta`; empty when there's nothing to lay over.
    public var meta: [String: JSONValue] {
        var settings: [String: JSONValue] = [:]
        if !deniedMCPServers.isEmpty {
            settings["deniedMcpServers"] = .array(
                deniedMCPServers.sorted().map { .object(["serverName": .string($0)]) })
        }
        if !disabledSkills.isEmpty {
            settings["skillOverrides"] = .object(
                Dictionary(uniqueKeysWithValues: disabledSkills.map { ($0, .string("off")) }))
        }
        guard !settings.isEmpty else { return [:] }
        return ["claudeCode": .object(["options": .object(["settings": .object(settings)])])]
    }
}
