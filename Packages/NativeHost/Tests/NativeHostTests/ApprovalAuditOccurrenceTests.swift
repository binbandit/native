import ACP
import Foundation
import NativeHostClient
import Testing

@testable import NativeHost
@testable import NativeHostProtocol

extension ApprovalAuditTests {
    @Test @HostActor func announcedApprovalUsesTheRealAdoptionPath() async throws {
        let rig = try PolicyRig(.unrestricted)
        let client = try await connect(rig)
        defer { rig.stop() }
        try await client.syncAgents([rig.agentSpec()])
        let parent = try await client.newSession(.init(agentID: "fake", cwd: rig.root.path()))
        let link = try #require(rig.core.agents["fake"])
        let childID = SessionID("announced-child")
        rig.core.adoptSubagent(childID, of: try #require(rig.core.sessions[parent.id]), on: link)
        let child = try #require(link.routes[childID])
        try stagePermission(rig, session: child, request: 101)
        let option = try #require(
            rig.core.sessions[child]?.mirror.state.pendingPermissions.first?.permission.options.first)
        #expect(try rig.core.store.sessions().contains { $0.id == child } == false)
        try await client.respondPermission(.init(sessionID: child, toolCallID: "same-tool", optionID: option.optionId))
        #expect(try records(rig.core.store).map(\.state) == [.requested, .decided, .deliveryAccepted])
        try stagePermission(rig, session: child, request: 102)
        rig.core.agentExited("fake", generation: link.generation)
        #expect(rig.core.sessions[child] == nil)
        #expect(try records(rig.core.store).last?.state == .withdrawn)
        await client.stop()
    }

    @Test(arguments: [false, true])
    @HostActor func sequentialApprovalsReuseAToolWithoutAcceptingStaleAnswers(_ restart: Bool) async throws {
        let rig = try PolicyRig(.unrestricted)
        let client = try await connect(rig)
        defer { rig.stop() }
        try await client.syncAgents([rig.agentSpec()])
        let session = try await client.newSession(.init(agentID: "fake", cwd: rig.root.path()))
        try stagePermission(rig, session: session.id, request: 201)
        let first = try #require(
            rig.core.sessions[session.id]?.mirror.state.pendingPermissions.first?.permission.options.first)
        let response = RespondPermissionParams(sessionID: session.id, toolCallID: "same-tool", optionID: first.optionId)
        let firstID = try #require(records(rig.core.store).first?.requestID)
        try await client.respondPermission(response)
        let activeRig: PolicyRig
        let activeClient: NativeHostClient
        if restart {
            rig.stop()
            await client.stop()
            activeRig = try PolicyRig(.unrestricted, root: rig.root)
            activeClient = try await connect(activeRig)
            _ = try await activeClient.attach(session.id)
            try await activeRig.core.load(try #require(activeRig.core.sessions[session.id]))
        } else {
            activeRig = rig
            activeClient = client
        }
        defer { activeRig.stop() }
        try stagePermission(activeRig, session: session.id, request: 202)
        let second = try #require(
            activeRig.core.sessions[session.id]?.mirror.state.pendingPermissions.first?.permission.options.first)
        await #expect(throws: (any Error).self) { try await activeClient.respondPermission(response) }
        await #expect(throws: (any Error).self) {
            try await activeClient.respondPermission(
                .init(sessionID: session.id, toolCallID: "same-tool", optionID: nil, approvalRequestID: firstID))
        }
        await #expect(throws: (any Error).self) {
            try await activeClient.respondPermission(
                .init(sessionID: session.id, toolCallID: "same-tool", optionID: nil))
        }
        try await activeClient.respondPermission(
            .init(sessionID: session.id, toolCallID: "same-tool", optionID: second.optionId))
        let rows = try records(activeRig.core.store)
        #expect(
            rows.map(\.state) == [.requested, .decided, .deliveryAccepted, .requested, .decided, .deliveryAccepted])
        #expect(rows[0].requestID != rows[3].requestID)
        #expect(activeRig.core.sessions[session.id]?.mirror.state.pendingPermissions.isEmpty == true)
        await activeClient.stop()
    }

    @Test @HostActor func firstAuditSchemaUpgradesWithoutLosingItsHistory() throws {
        let rig = try PolicyRig(.unrestricted)
        _ = try seed(rig.core)
        try rig.core.store.database.execute("DROP TABLE approval_pending; PRAGMA user_version = 11")
        let restarted = try HostCore(configuration: rig.core.configuration)
        #expect(try records(restarted.store).map(\.state) == [.requested, .withdrawn])
        #expect(try restarted.store.approvals().isEmpty)
        #expect(try restarted.store.database.query("PRAGMA user_version").first?.first?.integer == 12)
    }

    @HostActor private func stagePermission(_ rig: PolicyRig, session: HostSessionID, request: Int) throws {
        let live = try #require(rig.core.sessions[session])
        let agentSession = try #require(live.record.agentSessionID)
        let params: JSONValue = .object([
            "sessionId": .string(agentSession.rawValue),
            "toolCall": .object(["toolCallId": .string("same-tool"), "title": .string(Self.canary)]),
            "options": .array([
                .object([
                    "optionId": .string("allow"), "kind": .string("allow_once"), "name": .string("Allow"),
                ])
            ]),
        ])
        let message = JSONRPCPeer.Message(
            id: .int(request), method: "session/request_permission",
            line: try JSONEncoder().encode(JSONValue.object(["params": params])))
        rig.core.receiveRequest(message, from: try #require(rig.core.agents["fake"]))
    }
}
