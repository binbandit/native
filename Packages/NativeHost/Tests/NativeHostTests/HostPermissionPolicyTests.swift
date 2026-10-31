import ACP
import Foundation
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
        let previous = try PolicyRig(.unrestricted)
        let id = try previous.seedSession()
        let rig = try PolicyRig(
            HostPolicy(
                mode: .ordinary, capabilities: Set(HostCapability.allCases), forbiddenPermissionModes: ["full-access"]),
            root: previous.root)
        defer { rig.stop(); previous.stop() }
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
        let previous = try PolicyRig(.unrestricted)
        let id = try previous.seedInterruptedTurn()
        let rig = try PolicyRig(.unrestricted, root: previous.root)
        rig.core.start()
        defer { rig.stop(); previous.stop() }
        rig.core.apply(
            HostPolicy(
                mode: .ordinary, capabilities: Set(HostCapability.allCases), forbiddenPermissionModes: ["full-access"]))
        #expect(rig.core.sessions[id]?.record.isQueuePaused == true)
        #expect(rig.core.sessions[id]?.turn == nil)
        #expect(rig.core.sessions[id]?.queue.count == 1)
    }
    @Test func delayedPermissionUpdateCannotEscapeTightenedPolicy() async throws {
        let rig = try PolicyRig(.unrestricted)
        defer { rig.stop() }
        let client = try await rig.connect(.owner)
        try await client.syncAgents([rig.agentSpec()])
        let summary = try await client.newSession(NewSessionParams(agentID: "fake", cwd: rig.root.path()))
        _ = try await client.prompt(PromptParams(sessionID: summary.id, text: "slow 40"))
        let session = try #require(rig.core.sessions[summary.id])
        #expect(session.turn != nil)
        rig.core.apply(Self.noFullAccess)
        #expect(session.turn != nil)
        let link = try #require(rig.core.agents["fake"])
        let line = Data(
            #"{"params":{"sessionId":"fixture","update":{"sessionUpdate":"config_option_update","configOptions":[{"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"bypassPermissions","options":[{"value":"default","name":"Default"},{"value":"bypassPermissions","name":"Full access"}]}]}}}"#
                .utf8)
        rig.core.apply(try #require(AgentUpdate.parse(line)?.update), to: session, on: link)
        #expect(session.turn == nil)
        #expect(session.record.isQueuePaused)
        #expect(link.status != .ready)
        await client.stop()
    }

    @Test func delayedPermissionResponseCannotEscapeTightenedPolicy() async throws {
        let rig = try PolicyRig(.unrestricted)
        defer { rig.stop() }
        let release = rig.root.appending(path: "permission-release")
        let client = try await rig.connect(.owner)
        try await client.syncAgents([rig.agentSpec(env: ["FAKE_AGENT_PERMISSION_RELEASE": release.path()])])
        let summary = try await client.newSession(NewSessionParams(agentID: "fake", cwd: rig.root.path()))
        _ = try await client.prompt(PromptParams(sessionID: summary.id, text: "slow 40"))
        let session = try #require(rig.core.sessions[summary.id])
        let change = Task { @HostActor in
            try await rig.core.setConfigOption(
                SetConfigOptionParams(
                    sessionID: summary.id, configID: "mode", value: "bypassPermissions", permissionMode: "full-access"))
        }
        try await rig.waitUntil("pending permission RPC") {
            rig.agentReceived.contains("permission-pending\tbypassPermissions")
        }
        rig.core.apply(Self.noFullAccess)
        try Data().write(to: release)
        _ = await change.result
        #expect(session.turn == nil)
        #expect(session.record.isQueuePaused)
        #expect(rig.core.agents["fake"]?.status != .ready)
        await client.stop()
    }

    private static var noFullAccess: HostPolicy {
        HostPolicy(
            mode: .ordinary, capabilities: Set(HostCapability.allCases), forbiddenPermissionModes: ["full-access"])
    }

}
