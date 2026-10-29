import ACP
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite @HostActor
struct HostPermissionPolicyTests {
    @Test func canonicalAndLegacyCapsCannotBeOverriddenByClientIntent() {
        for forbidden in ["full-access", "bypassPermissions", "agent-full-access"] {
            let policy = HostPolicy(
                mode: .ordinary, capabilities: Set(HostCapability.allCases), forbiddenPermissionModes: [forbidden])
            #expect(!policy.allowsPermission("agent-full-access", intent: "ask-first"))
            #expect(!policy.allowsPermission("bypassPermissions"))
            #expect(!policy.allowsPermission("default", intent: "full-access"))
            #expect(policy.allowsPermission("default", intent: "ask-first"))
            #expect(!policy.allowsPermission("unknown", intent: "ask-first"))
        }
    }

    @Test func hostChecksSettingsAndRefusesUnreportedPermissions() throws {
        let rig = try PolicyRig(
            HostPolicy(
                mode: .ordinary, capabilities: Set(HostCapability.allCases), forbiddenPermissionModes: ["full-access"]))
        let id = try rig.seedSession()
        rig.core.start()
        defer { rig.stop() }
        let session = try #require(rig.core.sessions[id])
        #expect(throws: HostPolicyDenial.self) {
            try rig.core.requirePermission(in: session, value: "agent-full-access", intent: "ask-first")
        }
        #expect(throws: HostPolicyDenial.self) { try rig.core.requirePermission(in: session) }
        try rig.core.requirePermission(in: session, value: "default", intent: "ask-first")
        session.record.configChoices[SetConfigOptionParams.permissionChoiceKey] = "full-access"
        // An older client can still lower permissions without sending shared intent.
        try rig.core.requirePermission(in: session, value: "default")
    }

    @Test func tighteningHostCapPausesRecoveryAndQueues() throws {
        let rig = try PolicyRig(.unrestricted)
        let id = try rig.seedInterruptedTurn()
        rig.core.start()
        defer { rig.stop() }
        rig.core.apply(
            HostPolicy(
                mode: .ordinary, capabilities: Set(HostCapability.allCases), forbiddenPermissionModes: ["full-access"]))
        #expect(rig.core.sessions[id]?.record.isQueuePaused == true)
        #expect(rig.core.sessions[id]?.turn == nil)
        #expect(rig.core.sessions[id]?.queue.count == 1)
    }
}
