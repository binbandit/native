import ACP
import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

#if os(macOS)
import NativePolicy
#endif

@Suite(.serialized, .timeLimit(.minutes(2)))
@HostActor
struct HostAgentRouteAdmissionTests {
    private var route: AgentPrivateRoute {
        AgentPrivateRoute(
            identity: AgentRouteIdentity(
                routeID: "fixture", declarationID: "fixture-adapter", cliVersion: "1", adapterVersion: "2"),
            origin: "https://provider.internal.example", model: "fixture-model",
            authentication: .runtimeEnvironment("NATIVE_PROVIDER_KEY"))
    }

    private func declaration() -> HostAgentRouteAdmission.Declaration {
        let route = route
        return .init(
            spec: AgentSpec(id: "fixture", name: "Fixture", command: "/fixture/adapter", routeIdentity: route.identity),
            route: route,
            capabilities: AgentNetworkCapabilities(
                declarationID: route.identity.declarationID, cliVersion: "1", adapterVersion: "2",
                controls: route.requiredControls, qualified: true),
            purposes: Set(AgentRoutePurpose.allCases))
    }

    #if os(macOS)
    private var network: NativePolicy.Network {
        var network = NativePolicy.Network()
        if let origin = NetworkOrigin(route.origin) {
            network.services[.agentProvider] = .init(enabled: true, origins: [origin])
        }
        return network
    }

    @Test func hostApprovalAndCurrentNetworkAreBothRequired() throws {
        let declaration = declaration()
        #expect(throws: AgentRouteFailure.unqualified) {
            try HostAgentRouteAdmission.check(declaration.spec, policy: .unrestricted, network: network)
        }
        try HostAgentRouteAdmission.check(
            declaration.spec, policy: .unrestricted, network: network, declarations: [declaration])
        #expect(throws: AgentRouteFailure.networkDenied) {
            try HostAgentRouteAdmission.check(
                declaration.spec, policy: .unrestricted, network: nil, declarations: [declaration])
        }
        var revoked = network
        revoked.services[.agentProvider] = .init(enabled: false)
        #expect(throws: AgentRouteFailure.networkDenied) {
            try HostAgentRouteAdmission.check(
                declaration.spec, policy: .unrestricted, network: revoked, declarations: [declaration])
        }
        var restricted = network
        restricted.mode = .internalOnly
        #expect(throws: AgentRouteFailure.networkDenied) {
            try HostAgentRouteAdmission.check(
                declaration.spec, policy: .unrestricted, network: restricted, declarations: [declaration])
        }
    }

    @Test func forgedClientCannotChangeLaunchOrVersion() {
        let declaration = declaration()
        for key in ["command", "args", "env", "version", "route", "resolve", "auth"] {
            var spec = declaration.spec
            switch key {
            case "command": spec.command = "/forged/adapter"
            case "args": spec.args = ["--public-fallback"]
            case "env": spec.env = ["CODEX_CONFIG": "forged-secret"]
            case "version": spec.routeIdentity?.cliVersion = "newer"
            case "route": spec.routeIdentity?.routeID = "other"
            case "resolve": spec.resolveExecutables = ["CODEX_PATH": "forged"]
            default: spec.authMethods = [AuthMethod(id: "login", name: "Login", kind: .link)]
            }
            #expect(throws: AgentRouteFailure.self) {
                try HostAgentRouteAdmission.check(
                    spec, policy: .unrestricted, network: network, declarations: [declaration])
            }
        }
    }

    @Test func unknownAndMissingControlsAndAuxiliaryPurposesDeny() {
        let declaration = declaration()
        for control in route.requiredControls.union([.unknown]) {
            var capabilities = declaration.capabilities
            if control == .unknown {
                capabilities.controls.insert(.unknown)
            } else {
                capabilities.controls.remove(control)
            }
            let altered = HostAgentRouteAdmission.Declaration(
                spec: declaration.spec, route: route, capabilities: capabilities, purposes: declaration.purposes)
            #expect(throws: AgentRouteFailure.unsupportedControl) {
                try HostAgentRouteAdmission.check(
                    altered.spec, policy: .unrestricted, network: network, declarations: [altered])
            }
        }
        for purpose in AgentRoutePurpose.allCases {
            let altered = HostAgentRouteAdmission.Declaration(
                spec: declaration.spec, route: route, capabilities: declaration.capabilities,
                purposes: declaration.purposes.subtracting([purpose]))
            #expect(throws: AgentRouteFailure.unsupportedControl) {
                try HostAgentRouteAdmission.check(
                    altered.spec, policy: .unrestricted, network: network, declarations: [altered])
            }
        }
    }

    @Test func requiredProxyCAAndAuthenticationControlsDoNotInheritSupport() {
        let declaration = declaration()
        for kind in ["proxy", "bypass", "ca", "native-auth"] {
            var route = route
            switch kind {
            case "proxy": route.proxyOrigin = "https://proxy.internal.example"
            case "bypass": route.bypassProxy = true
            case "ca": route.customCAFile = "/fixture/ca.pem"
            default: route.authentication = .nativeCredential("fixture-reference")
            }
            let altered = HostAgentRouteAdmission.Declaration(
                spec: declaration.spec, route: route, capabilities: declaration.capabilities,
                purposes: declaration.purposes)
            #expect(throws: AgentRouteFailure.unsupportedControl) {
                try HostAgentRouteAdmission.check(
                    altered.spec, policy: .unrestricted, network: network, declarations: [altered])
            }
        }
    }

    #endif

    @Test func interruptedPrivateRouteNeverRecoversIntoAnOrdinaryLaunch() async throws {
        let previous = try PolicyRig(.unrestricted)
        let sessionID = try previous.seedInterruptedTurn()
        var spec = previous.agentSpec()
        spec.routeIdentity = route.identity
        try previous.core.store.replaceAgents([spec])
        let restarted = try PolicyRig(.unrestricted, root: previous.root)
        restarted.core.start()
        defer { restarted.stop() }
        try await restarted.waitUntil("the denied recovery to conclude") {
            (try? restarted.core.store.unfinishedTurns().isEmpty) == true
        }
        #expect(restarted.core.sessions[sessionID]?.record.isQueuePaused == true)
        restarted.expectNothingRan()
    }

    @Test func hostEntryPointDeniesBeforeEnvironmentOrProcess() async throws {
        let rig = try PolicyRig(.unrestricted)
        defer { rig.stop() }
        var spec = rig.agentSpec()
        spec.routeIdentity = route.identity
        try rig.core.syncAgents([spec])
        let error = await #expect(throws: HostPolicyDenial.self) { _ = try await rig.core.readyAgent(spec.id) }
        #expect(error?.localizedDescription.contains("forged") == false)
        rig.expectNothingRan()
        #expect(rig.probe.shellReads == 0)
        // Restarting the host does not promote a stored client declaration to an approval.
        let restarted = try PolicyRig(.unrestricted, root: rig.root)
        defer { restarted.stop() }
        try restarted.core.syncAgents([spec])
        await #expect(throws: HostPolicyDenial.self) { _ = try await restarted.core.readyAgent(spec.id) }
        restarted.expectNothingRan()
    }

    @Test func deniedIdentityNeverEchoesClientContent() async throws {
        let rig = try PolicyRig(
            HostPolicy(
                mode: .ordinary, capabilities: Set(HostCapability.allCases), allowedAgents: ["other"]))
        defer { rig.stop() }
        var spec = rig.agentSpec()
        spec.name = "canary-content"
        spec.routeIdentity = route.identity
        try rig.core.syncAgents([spec])
        let error = await #expect(throws: HostPolicyDenial.self) { _ = try await rig.core.readyAgent(spec.id) }
        #expect(error?.localizedDescription.contains("canary-content") == false)
        rig.expectNothingRan()
    }

    @Test func directLinkAlsoDeniesWithoutReadingEnvironment() async throws {
        let declaration = declaration()
        let link = AgentLink(spec: declaration.spec)
        let probe = PolicyProbe()
        await #expect(throws: AgentRouteFailure.unqualified) {
            try await link.ensureStarted(
                environment: {
                    probe.count("shell"); return [:]
                }, clientInfo: Implementation(name: "fixture", version: "1"),
                onEvent: { _, _ in })
        }
        #expect(probe.shellReads == 0)
        #expect(link.processIdentifier == nil)
    }

    @Test func ordinaryLegacySpecsRemainCompatible() throws {
        let spec = AgentSpec(id: "fixture", name: "Fixture", command: "fixture")
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(AgentSpec.self, from: data)
        #expect(decoded.routeIdentity == nil)
        try HostAgentRouteAdmission.check(decoded, policy: .unrestricted)
        #expect(HostAgentRouteAdmission.approved.isEmpty)
    }
}
