import ACP
import Foundation

/// Codex applies a policy when it launches, through `CODEX_CONFIG` (`CodexConfigOverrides` in the
/// ACP package, which has the adapter's details and its known limit). There's no per-session
/// equivalent, so intents for one project can't be applied.
struct CodexPolicyTranslator: SessionPolicyTranslator {
    func launchEnvironment(for policy: SessionPolicy) -> [String: String] {
        let reach = policy.allProjectsOnly
        return CodexConfigOverrides(
            disabledMCPServers: Set(reach.disabledMCPServers.map(\.name)),
            disabledSkills: reach.disabledSkills.compactMap(\.path),
            threadUnloadDelay: Self.threadUnloadDelay
        ).environment
    }

    /// Native closes a session after it's sat unused (`AppModel.sessionIdleTimeout`); a minute later
    /// Codex lets go of it and its MCP servers too (docs/performance.md).
    static let threadUnloadDelay = Duration.seconds(60)

    /// Auto review (`agent`) only asks about what its reviewer flags, and full access never asks (codex-acp 2.2.2).
    func approvesToolCallsUnasked(inMode mode: String) -> Bool {
        ["agent", "agent-full-access"].contains(mode)
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
