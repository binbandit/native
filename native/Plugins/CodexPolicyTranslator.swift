import ACP
import Foundation

/// Codex applies a policy when it launches: its ACP adapter merges the JSON in `CODEX_CONFIG` into
/// every session's config, and `mcp_servers.<name>.enabled = false` keeps that server from starting.
/// There's no per-session equivalent, so intents for one project can't be applied.
struct CodexPolicyTranslator: SessionPolicyTranslator {
    func launchEnvironment(for policy: SessionPolicy) -> [String: String] {
        let names = Set(policy.allProjectsOnly.disabledMCPServers.map(\.name)).sorted()
        guard !names.isEmpty else { return [:] }
        let servers = JSONValue.object(Dictionary(uniqueKeysWithValues: names.map { ($0, JSONValue.object(["enabled": .bool(false)])) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(["mcp_servers": servers])) else { return [:] }
        return ["CODEX_CONFIG": String(decoding: data, as: UTF8.self)]
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers: .atLaunch
        case .skills: .unsupported("Codex skills can't be turned off from Native yet.")
        }
    }
}
