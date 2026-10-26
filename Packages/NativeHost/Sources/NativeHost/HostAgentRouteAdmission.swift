import ACP
import Foundation
import NativeHostProtocol
import NativeNetwork
import NativePolicy

/// Admission only, never containment of arbitrary agent descendants. The production list is empty
/// until reviewed fixture evidence AND executable/environment admission qualify a route on this host.
enum HostAgentRouteAdmission {
    struct Declaration: Sendable {
        let spec: AgentSpec
        let route: AgentPrivateRoute
        let capabilities: AgentNetworkCapabilities
        let purposes: Set<AgentRoutePurpose>
    }

    static let approved: [Declaration] = []

    /// The host's current network snapshot must be supplied independently of client data when a
    /// production route is qualified. Nil is unavailable, never an unrestricted default.
    static func check(
        _ spec: AgentSpec, policy: HostPolicy, network: NativePolicy.Network? = nil,
        declarations: [Declaration] = approved
    ) throws {
        guard policy.allows(agent: spec.id) else { throw AgentRouteFailure.unqualified }
        guard let identity = spec.routeIdentity else {
            guard policy.mode == .ordinary else { throw AgentRouteFailure.unqualified }
            return
        }
        guard let declaration = declarations.first(where: { $0.route.identity == identity }),
            declaration.capabilities.qualified
        else { throw AgentRouteFailure.unqualified }
        let capabilities = declaration.capabilities
        guard declaration.spec == spec,
            capabilities.declarationID == identity.declarationID,
            capabilities.cliVersion == identity.cliVersion, capabilities.adapterVersion == identity.adapterVersion
        else { throw AgentRouteFailure.declarationMismatch }
        guard !capabilities.controls.contains(.unknown),
            declaration.route.requiredControls.isSubset(of: capabilities.controls),
            declaration.purposes == Set(AgentRoutePurpose.allCases)
        else { throw AgentRouteFailure.unsupportedControl }
        let route = declaration.route
        guard let origin = NetworkOrigin(route.origin), ["https", "http"].contains(origin.scheme),
            let url = URL(string: route.origin), !route.model.isEmpty
        else { throw AgentRouteFailure.invalidRoute }
        // NetworkInventory deliberately still marks agents.provider externalProcess. Even a
        // fabricated qualified declaration cannot turn this into restricted transport enforcement.
        do {
            try NetworkAdmission.check(service: .agentProvider, destination: .url(url), policy: network)
            if let proxy = route.proxyOrigin {
                guard let proxyOrigin = NetworkOrigin(proxy), proxyOrigin.scheme == "https",
                    let proxyURL = URL(string: proxy)
                else { throw AgentRouteFailure.invalidRoute }
                try NetworkAdmission.check(service: .agentProvider, destination: .url(proxyURL), policy: network)
            }
        } catch let failure as AgentRouteFailure {
            throw failure
        } catch {
            throw AgentRouteFailure.networkDenied
        }
    }
}
