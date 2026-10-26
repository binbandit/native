import ACP
import Foundation
import NativeHostProtocol

extension AppModel {
    /// There is deliberately no settings surface or enabled route yet. All uses of an admitted
    /// agent (including generated text and recovery) select the same host-checked spec identity.
    func composingPrivateRoute(_ route: AgentPrivateRoute, for spec: AgentSpec) throws -> AgentSpec {
        let id = AgentDefinition.ID(rawValue: spec.id)
        guard let declaration = plugins.agents.first(where: { $0.id == id })?.manifest.networkCapabilities,
            declaration.qualified, declaration.declarationID == route.identity.declarationID,
            declaration.cliVersion == route.identity.cliVersion,
            declaration.adapterVersion == route.identity.adapterVersion,
            route.requiredControls.isSubset(of: declaration.controls),
            let translator = plugins.policyTranslator(for: id) as? any AgentPrivateRouteTranslator
        else { throw AgentRouteFailure.unqualified }
        guard spec.env.isEmpty else { throw AgentRouteFailure.conflictingConfiguration }
        var spec = spec
        spec.env = try translator.privateRouteEnvironment(for: plugins.launchPolicy(for: id), route: route)
        spec.routeIdentity = route.identity
        return spec
    }

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
