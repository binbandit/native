import ACP
import Foundation

/// Claude Code applies a policy per session: its ACP adapter passes `_meta.claudeCode.options` to
/// the Agent SDK, whose programmatic settings tier merges `deniedMcpServers` with the user's own
/// settings, so a denied server isn't started for that session. The user's files are untouched.
struct ClaudeCodePolicyTranslator: SessionPolicyTranslator {
    func sessionMeta(for policy: SessionPolicy) -> [String: JSONValue] {
        let names = Set(policy.disabledMCPServers.map(\.name)).sorted()
        guard !names.isEmpty else { return [:] }
        let denied = JSONValue.array(names.map { .object(["serverName": .string($0)]) })
        return ["claudeCode": .object(["options": .object(["settings": .object(["deniedMcpServers": denied])])])]
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers: .perSession
        case .skills: .unsupported("Claude Code skills can't be turned off from Native yet.")
        }
    }
}
