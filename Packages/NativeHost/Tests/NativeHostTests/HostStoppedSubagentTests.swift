import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Stopped subagent transcripts", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostStoppedSubagentTests {
    @Test("Fresh clients retain descendant identities, history and routes after Stop", arguments: [false, true])
    func retainsDescendants(nested: Bool) async throws {
        let rig = try HostStopCommandRig()
        defer { rig.cleanup() }
        let recorder = try await rig.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: rig.harness.root.path, attach: true))
        let parent = try #require(rig.core.sessions[summary.id])
        let link = try #require(rig.core.agents["fake"])
        var owner = parent
        var descendants: [HostSession] = []
        for index in 0..<(nested ? 2 : 1) {
            let id = SessionID("child-\(index)")
            let data = Data(
                #"{"params":{"sessionId":"parent","update":{"sessionUpdate":"subagent_update","sessionId":"\#(id.rawValue)","state":{"state":"running"}}}}"#
                    .utf8)
            let announcement = try #require(AgentUpdate.parse(data))
            rig.core.apply(announcement.update, to: owner, on: link)
            let child = try #require(rig.core.sessions.values.first { $0.record.agentSessionID == id })
            rig.core.append(
                .update(
                    .object([
                        "sessionUpdate": .string("agent_message_chunk"),
                        "content": .object(["type": .string("text"), "text": .string("Child history")]),
                    ])), to: child)
            rig.core.append(
                .update(
                    .object([
                        "sessionUpdate": .string("tool_call"), "toolCallId": .string("work"),
                        "title": .string("Child command"), "kind": .string("execute"), "status": .string("in_progress"),
                    ])), to: child)
            child.pendingQuestions = [(id: "question", request: .int(71))]
            descendants.append(child)
            owner = child
        }
        let buffered = try #require(
            AgentUpdate.parse(
                Data(
                    #"{"params":{"sessionId":"child-0","update":{"sessionUpdate":"subagent_update","sessionId":"child-1","state":{"state":"idle","stopReason":"cancelled"}}}}"#
                        .utf8)))
        let generation = link.generation
        let previous = link.onChange
        link.onChange = {
            previous?()
            if nested && link.generation > generation && link.status == .ready {
                link.buffer(buffered.update, for: SessionID("child-0"))
            }
        }
        defer { link.onChange = previous }
        _ = try await recorder.client.prompt(PromptParams(sessionID: parent.id, text: "stubborn 100"))
        try await recorder.wait("the parent turn") { await $0.agentText(parent.id).contains("tick 1") }
        try await recorder.client.cancel(parent.id)
        try await recorder.client.cancel(parent.id)
        try await recorder.wait("the stopped parent") { await $0.turnsEnded(parent.id) == ["cancelled"] }
        try await recorder.wait("the reattached parent") { _ in await !parent.needsLoad }
        let reader = try await rig.connect()
        for child in descendants {
            #expect(rig.core.sessions[child.id] === child)
            let id = try #require(child.record.agentSessionID)
            #expect(link.routes[id] == child.id)
            #expect(rig.core.sessions.values.count { $0.record.agentSessionID == id } == 1)
            let summary = try await reader.client.attach(child.id)
            #expect(await reader.agentText(child.id) == "Child history")
            #expect(!summary.needsApproval)
            #expect(summary.lastStopReason == "cancelled")
            #expect(
                await reader.mirror(child.id).state.items.contains {
                    if case .toolCall(let call) = $0 { call.status == .cancelled } else { false }
                })
            #expect(!child.isWorkingInBackground)
        }
        #expect(!parent.isWorkingInBackground)
        await reader.stop()
        await recorder.stop()
    }
}
