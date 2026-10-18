import ACP
import Foundation

/// Codex applies a policy when it launches: its ACP adapter (codex-acp 2.2.2) merges the JSON in
/// `CODEX_CONFIG` into every session's config, and `mcp_servers.<name>.enabled = false` keeps that
/// server from starting. The keys are dotted paths, because the adapter replaces the whole
/// `mcp_servers` table when a session brings servers of its own.
///
/// Known limit: when a session does bring servers (Native's orchestration server, say), Codex gets
/// both that table and the dotted key in one unordered map, and the server stays off only when the
/// key happens to apply second. docs/agent-session-overrides.md has the details and the fix the
/// adapter needs. There's no per-session equivalent, so intents for one project can't be applied.
struct CodexPolicyTranslator: SessionPolicyTranslator {
    func launchEnvironment(for policy: SessionPolicy) -> [String: String] {
        let names = Set(policy.allProjectsOnly.disabledMCPServers.map(\.name)).sorted()
        guard !names.isEmpty else { return [:] }
        let overrides = JSONValue.object(
            Dictionary(uniqueKeysWithValues: names.map { ("mcp_servers.\($0).enabled", JSONValue.bool(false)) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(overrides) else { return [:] }
        return ["CODEX_CONFIG": String(decoding: data, as: UTF8.self)]
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers: .atLaunch
        case .skills: .atLaunch
        }
    }
}
