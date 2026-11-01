import ACP
import Foundation
import NativeHostProtocol
import Testing

@Suite struct HostAgentCapabilitiesTests {
    @Test func runningSnapshotSuppliesNegotiationWithoutAnotherRPC() throws {
        let initialize = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"{"protocolVersion":1,"agentCapabilities":{"sessionCapabilities":{"resume":{}}}}"#.utf8))
        var agent = HostAgent(id: "fixture", name: "Fixture", state: .ready, initialize: initialize)
        #expect(agent.effectiveCapabilities()[.resume].support == .supported)
        agent.state = .stopped
        #expect(agent.effectiveCapabilities()[.resume].support == .unknown)
    }

    @Test func malformedNegotiationDoesNotImplySupport() {
        let agent = HostAgent(id: "fixture", name: "Fixture", state: .ready, initialize: .object([:]))
        #expect(agent.effectiveCapabilities()[.resume].reason == .notNegotiated)
    }
}
