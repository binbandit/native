import ACP
import Foundation

/// Codex applies a policy when it launches: its ACP adapter merges the JSON in `CODEX_CONFIG` into
/// every session's config: `mcp_servers.<name>.enabled = false` keeps that server from starting, and a
/// `skills.config` entry with a SKILL.md path and `enabled = false` hides that skill from the model
/// (verified with codex-acp 2.2.2; its `$skill` command list still shows it).
/// There's no per-session equivalent, so intents for one project can't be applied.
struct CodexPolicyTranslator: SessionPolicyTranslator {
    func launchEnvironment(for policy: SessionPolicy) -> [String: String] {
        let launch = policy.allProjectsOnly
        var config: [String: JSONValue] = [:]
        let names = Set(launch.disabledMCPServers.map(\.name)).sorted()
        if !names.isEmpty {
            config["mcp_servers"] = .object(
                Dictionary(uniqueKeysWithValues: names.map { ($0, JSONValue.object(["enabled": .bool(false)])) }))
        }
        // Codex matches skills by their SKILL.md path; names alone can't reach it.
        let skillFiles = Set(
            launch.disabledSkills.compactMap(\.path).map { $0.hasSuffix("/SKILL.md") ? $0 : $0 + "/SKILL.md" }
        ).sorted()
        if !skillFiles.isEmpty {
            config["skills"] = .object([
                "config": .array(skillFiles.map { .object(["path": .string($0), "enabled": .bool(false)]) })
            ])
        }
        guard !config.isEmpty else { return [:] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(config)) else { return [:] }
        return ["CODEX_CONFIG": String(decoding: data, as: UTF8.self)]
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers: .atLaunch
        case .skills: .atLaunch
        }
    }
}
