import ACP
import Foundation

/// Claude Code applies a policy per session, through settings laid over each session
/// (`ClaudeCodeSessionSettings` in the ACP package, which has the adapter's details).
struct ClaudeCodePolicyTranslator: SessionPolicyTranslator {
    func sessionMeta(for policy: SessionPolicy) -> [String: JSONValue] {
        ClaudeCodeSessionSettings(
            deniedMCPServers: Set(policy.disabledMCPServers.map(\.name)),
            disabledSkills: Set(policy.disabledSkills.compactMap(\.name))
        ).meta
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers: .perSession
        case .skills: .perSession
        }
    }
}
