import Foundation

extension AppModel {
    /// Agents running with a launch policy older than plugins' current one (an MCP server switched
    /// off for all projects, say, on an agent that applies that at launch).
    var agentsWithPendingLaunchPolicy: [AgentRuntime] {
        agents.filter { $0.isReady && $0.launchPolicyEnvironment != plugins.launchEnvironment(for: $0.agent.id) }
    }

    /// Restarts agents whose launch policy changed, so new sessions get it: each one only while
    /// none of its sessions is working, unless `force` (the user's "Apply to running sessions").
    /// Never mid-turn on its own.
    func applyLaunchPolicies(force: Bool = false) async {
        for runtime in agentsWithPendingLaunchPolicy where force || !isWorking(runtime.agent.id) {
            await restart(runtime.agent.id)
        }
    }

    /// Whether any open session of `agent` is in a turn.
    func isWorking(_ agent: AgentDefinition.ID) -> Bool {
        sessions.open(of: agent).contains { $0.phase == .prompting || $0.isRunningHiddenCommand }
    }
}
