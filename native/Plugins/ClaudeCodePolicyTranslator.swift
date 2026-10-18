import ACP
import Foundation

/// Claude Code applies a policy per session: its ACP adapter passes `_meta.claudeCode.options` to
/// the Agent SDK, whose programmatic settings tier merges `deniedMcpServers` with the user's own
/// settings, so a denied server isn't started for that session; `skillOverrides` set to "off" hides a
/// skill from the model and the slash commands (plugin-qualified skills excepted, verified with
/// claude-agent-acp 0.93.0). The user's files are untouched.
struct ClaudeCodePolicyTranslator: SessionPolicyTranslator {
    func sessionMeta(for policy: SessionPolicy) -> [String: JSONValue] {
        var settings: [String: JSONValue] = [:]
        let servers = Set(policy.disabledMCPServers.map(\.name)).sorted()
        if !servers.isEmpty {
            settings["deniedMcpServers"] = .array(servers.map { .object(["serverName": .string($0)]) })
        }
        let skills = Set(policy.disabledSkills.compactMap(\.name))
        if !skills.isEmpty {
            settings["skillOverrides"] = .object(Dictionary(uniqueKeysWithValues: skills.map { ($0, .string("off")) }))
        }
        guard !settings.isEmpty else { return [:] }
        return ["claudeCode": .object(["options": .object(["settings": .object(settings)])])]
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers: .perSession
        case .skills: .perSession
        }
    }
}
