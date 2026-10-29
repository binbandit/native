import ACP
import Foundation

/// Claude Code applies a policy per session, through settings laid over each session
/// (`ClaudeCodeSessionSettings` in the ACP package, which has the adapter's details).
struct ClaudeCodePolicyTranslator: SessionPolicyTranslator {
    var permissionMapping: TaskPermissionMapping { ClaudeCodeSessionSettings.permissionMapping }

    func sessionMeta(for policy: SessionPolicy) -> [String: JSONValue] {
        ClaudeCodeSessionSettings(
            deniedMCPServers: Set(policy.disabledMCPServers.map(\.name)),
            disabledSkills: Set(policy.disabledSkills.compactMap(\.name))
        ).meta
    }

    /// Auto lets a classifier decide and bypass and don't-ask never prompt (claude-agent-acp 0.93.0).
    func approvesToolCallsUnasked(inMode mode: String) -> Bool {
        ["auto", "bypassPermissions", "dontAsk"].contains(mode)
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers: .perSession
        case .skills: .perSession
        }
    }
}
