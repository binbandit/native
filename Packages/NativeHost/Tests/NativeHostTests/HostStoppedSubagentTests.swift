import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Stopped subagent transcripts", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostStoppedSubagentTests {
    @Test(
        "Fresh clients retain descendant identities, history and routes after Stop", arguments: [false, true],
        [false, true])
    func retainsDescendants(nested: Bool, resumes: Bool) async throws {
        let rig = try HostStopCommandRig()
        rig.harness.agentEnvironment["FAKE_AGENT_CHILD_IDS"] = nested ? "child-0,child-1" : "child-0"
        if !resumes { rig.harness.agentEnvironment["FAKE_AGENT_NO_RESUME"] = "1" }
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
            let expected = resumes ? "Child history\nFresh child update" : "Child history"
            #expect(await reader.agentText(child.id) == expected)
            #expect(!summary.needsApproval)
            #expect(summary.lastStopReason == "cancelled")
            #expect(
                await reader.mirror(child.id).state.items.contains {
                    if case .toolCall(let call) = $0 { call.status == .cancelled } else { false }
                })
            #expect(!child.isWorkingInBackground)
            let live = try #require(
                AgentUpdate.parse(
                    Data(
                        #"{"params":{"sessionId":"child","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Live child traffic"}}}}"#
                            .utf8)))
            rig.core.apply(live.update, to: child, on: link)
            try await reader.wait("fresh child traffic") { await $0.agentText(child.id).contains("Live child traffic") }
            let after = await reader.agentText(child.id)
            #expect(after.components(separatedBy: "Child history").count == 2)
        }
        #expect(!parent.isWorkingInBackground)
        await reader.stop()
        await recorder.stop()
    }
    @Test("Fresh child output and settings survive the load response and parent restoration", arguments: [false, true])
    func freshChildrenAfterLoad(atBoundary: Bool) async throws {
        let rig = try HostStopCommandRig()
        rig.harness.agentEnvironment["FAKE_AGENT_CHILD_IDS"] = "child-0"
        rig.harness.agentEnvironment["FAKE_AGENT_NO_RESUME"] = "1"
        rig.harness.agentEnvironment[atBoundary ? "FAKE_AGENT_CHILD_AFTER_LOAD" : "FAKE_AGENT_CHILD_ON_RESTORE"] = "1"
        defer { rig.cleanup() }
        let recorder = try await rig.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: rig.harness.root.path, attach: true))
        let parent = try #require(rig.core.sessions[summary.id])
        let link = try #require(rig.core.agents["fake"])
        let announcement = try #require(
            AgentUpdate.parse(
                Data(
                    #"{"params":{"sessionId":"parent","update":{"sessionUpdate":"subagent_update","sessionId":"child-0","state":{"state":"running"}}}}"#
                        .utf8)))
        rig.core.apply(announcement.update, to: parent, on: link)
        let child = try #require(rig.core.sessions.values.first { $0.record.agentSessionID == SessionID("child-0") })
        rig.core.append(
            .update(
                .object([
                    "sessionUpdate": .string("agent_message_chunk"),
                    "content": .object(["type": .string("text"), "text": .string("Child history")]),
                ])), to: child)
        try await recorder.client.setConfigOption(
            SetConfigOptionParams(sessionID: parent.id, configID: "model", value: "beta"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: parent.id, text: "stubborn 100"))
        try await recorder.wait("the parent turn") { await $0.agentText(parent.id).contains("tick 1") }
        try await recorder.client.cancel(parent.id)
        try await recorder.client.cancel(parent.id)
        try await recorder.wait("the stopped parent") { await $0.turnsEnded(parent.id) == ["cancelled"] }
        try await recorder.wait("the restored parent settings") { _ in await !parent.needsLoad }
        #expect(parent.record.configChoices["model"] == "beta")
        let reader = try await rig.connect()
        _ = try await reader.client.attach(child.id)
        let text = await reader.agentText(child.id)
        #expect(text.contains(atBoundary ? "Fresh at boundary" : "Fresh during restore"))
        #expect(text.components(separatedBy: "Child history").count == 2)
        #expect(await reader.mirror(child.id).state.configOptions.map(\.id) == ["mode", "effort", "model"])
        await reader.stop()
        await recorder.stop()
    }

}
