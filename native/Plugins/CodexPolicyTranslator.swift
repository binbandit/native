import ACP
import Foundation

/// Codex applies a policy when it launches, through `CODEX_CONFIG` (`CodexConfigOverrides` in the
/// ACP package, which has the adapter's details and its known limit). There's no per-session
/// equivalent, so intents for one project can't be applied.
struct CodexPolicyTranslator: AgentPrivateRouteTranslator {
    var permissionMapping: TaskPermissionMapping { CodexConfigOverrides.permissionMapping }

    func launchEnvironment(for policy: SessionPolicy) -> [String: String] {
        let reach = policy.allProjectsOnly
        return CodexConfigOverrides(
            disabledMCPServers: Set(reach.disabledMCPServers.map(\.name)),
            disabledSkills: reach.disabledSkills.compactMap(\.path)
        ).environment
    }

    /// Candidate composition for controlled qualification. The host still denies this unqualified pair.
    func privateRouteEnvironment(for policy: SessionPolicy, route: AgentPrivateRoute) throws -> [String: String] {
        let reach = policy.allProjectsOnly
        return try CodexConfigOverrides(
            disabledMCPServers: Set(reach.disabledMCPServers.map(\.name)),
            disabledSkills: reach.disabledSkills.compactMap(\.path)
        ).environment(for: route)
    }

    /// Auto review (`agent`) only asks about what its reviewer flags, and full access never asks (codex-acp 2.2.2).
    func approvesToolCallsUnasked(inMode mode: String) -> Bool {
        ["agent", "agent-full-access"].contains(mode)
    }

    func support(for kind: SessionPolicySupport.Kind) -> SessionPolicySupport {
        switch kind {
        case .mcpServers:
            .atLaunch(
                caveat:
                    "Codex may still load it in tasks that bring Native's own tools, until its adapter is updated.")
        case .skills: .atLaunch(caveat: nil)
        }
    }
}
