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
        let skills = skillsConfig(for: policy)
        guard !names.isEmpty || !skills.isEmpty else { return [:] }
        // Both forms: the nested table survives once the adapter merges session servers into it
        // (the change in docs/agent-session-overrides.md), and the dotted keys cover the adapter
        // pinned today as far as it allows.
        let off = JSONValue.object(["enabled": .bool(false)])
        var overrides = Dictionary(
            uniqueKeysWithValues: names.map { ("mcp_servers.\($0).enabled", JSONValue.bool(false)) })
        if !names.isEmpty {
            overrides["mcp_servers"] = .object(Dictionary(uniqueKeysWithValues: names.map { ($0, off) }))
        }
        overrides.merge(skills) { $1 }
        let config = JSONValue.object(overrides)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return [:] }
        return ["CODEX_CONFIG": String(decoding: data, as: UTF8.self)]
    }

    /// Skills off in every session: Codex matches them by SKILL.md path in `skills.config`, and
    /// hides each from the model (verified with codex-acp 2.2.2 and gpt-6.1-sol; its `$skill`
    /// command list still shows them, since the adapter builds that from `skills/list`).
    private func skillsConfig(for policy: SessionPolicy) -> [String: JSONValue] {
        let files = Set(
            policy.allProjectsOnly.disabledSkills.compactMap(\.path).map {
                $0.hasSuffix("/SKILL.md") ? $0 : $0 + "/SKILL.md"
            }
        ).sorted()
        guard !files.isEmpty else { return [:] }
        let entries = files.map { JSONValue.object(["path": .string($0), "enabled": .bool(false)]) }
        return ["skills": .object(["config": .array(entries)])]
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers:
            .atLaunch(
                caveat:
                    "Codex may still load it in sessions that bring Native's own tools, until its adapter is updated.")
        case .skills: .atLaunch(caveat: nil)
        }
    }
}
