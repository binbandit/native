import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Idle subagent transcripts", .serialized, .timeLimit(.minutes(1)))
@HostActor
struct HostIdleSubagentTests {
    @Test(
        "Fresh clients can read completed descendants before and after quiet parent resume", arguments: [false, true])
    func retainsDescendants(nested: Bool) async throws {
        let host = try await ExecHost.make()
        let core = host.core
        defer { for link in core.agents.values { link.endNow() } }
        let recorder = Recorder(client: host.owner)
        await recorder.listen()
        var spec = host.harness.agentSpec
        spec.idleUnloadTimeout = 600
        try await host.owner.syncAgents([spec])
        let summary = try await host.owner.newSession(
            NewSessionParams(agentID: "fake", cwd: host.projectPath, attach: true))
        _ = try await host.owner.prompt(PromptParams(sessionID: summary.id, text: "hello"))
        try await recorder.wait("the parent turn") { await $0.turnsEnded(summary.id) == ["end_turn"] }
        let parent = try #require(core.sessions[summary.id])
        let link = try #require(core.agents["fake"])
        try announce(SessionID("child"), of: parent, on: link, in: core)
        let child = try #require(core.sessions.values.first { $0.record.parentID == parent.id })
        var descendants = [child]
        if nested {
            try announce(SessionID("grandchild"), of: child, on: link, in: core)
            descendants.append(try #require(core.sessions.values.first { $0.record.parentID == child.id }))
        }
        for descendant in descendants {
            core.append(
                .update(
                    .object([
                        "sessionUpdate": .string("agent_message_chunk"),
                        "content": .object(["type": .string("text"), "text": .string("Completed child work")]),
                    ])), to: descendant)
        }

        let later = Date.now.addingTimeInterval(601)
        let waiting = try #require(descendants.last)
        let waitingID = try #require(waiting.record.agentSessionID)
        let ownerID = try #require(waiting.record.parentID)
        let owner = try #require(core.sessions[ownerID])
        try announce(waitingID, state: "running", of: owner, on: link, in: core)
        core.unloadIdleSessions(now: later)
        #expect(!parent.needsLoad)
        try announce(waitingID, of: owner, on: link, in: core)
        waiting.pendingPermissions["tool"] = .int(1)
        core.unloadIdleSessions(now: later)
        #expect(!parent.needsLoad)
        waiting.pendingPermissions = [:]
        waiting.pendingQuestions = [(id: "question", request: .int(2))]
        core.unloadIdleSessions(now: later)
        #expect(!parent.needsLoad)
        waiting.pendingQuestions = []
        waiting.hiddenCommand = HiddenCommandCapture()
        core.unloadIdleSessions(now: later)
        #expect(!parent.needsLoad)
        waiting.hiddenCommand = nil

        // The first pass closes the parent; a later one stops the adapter once the agent answers the
        // close, which can take well over 100 ms on a busy runner.
        core.unloadIdleSessions(now: later)
        let stopped = await HostKeepAwakeTests.eventually(within: .seconds(10)) {
            core.unloadIdleSessions(now: later)
            return link.status == .stopped
        }
        #expect(stopped)

        let reader = try await host.connect(.owner, name: "fresh reader")
        let reading = Recorder(client: reader)
        await reading.listen()
        for descendant in descendants {
            _ = try await reader.attach(descendant.id)
            #expect(await reading.agentText(descendant.id) == "Completed child work")
        }
        #expect(link.status == .stopped)

        _ = try await host.owner.prompt(PromptParams(sessionID: parent.id, text: "again"))
        try await recorder.wait("the resumed parent") { await $0.turnsEnded(parent.id).count == 2 }
        for descendant in descendants {
            #expect(core.sessions[descendant.id] === descendant)
            let agentID = try #require(descendant.record.agentSessionID)
            #expect(link.routes[agentID] == descendant.id)
            let ownerID = try #require(descendant.record.parentID)
            let owner = try #require(core.sessions[ownerID])
            try announce(agentID, of: owner, on: link, in: core)
            #expect(core.sessions.values.count { $0.record.agentSessionID == agentID } == 1)
            #expect(core.sessions[descendant.id] === descendant)
            _ = try await reader.attach(descendant.id)
            #expect(await reading.agentText(descendant.id) == "Completed child work")
        }
        #expect(host.harness.received.contains { $0.hasPrefix("resume\t") })
        await reader.stop()
        await host.owner.stop()
        await core.stopAgentsAndExit(confirmationWait: .zero)
    }

    private func announce(
        _ id: SessionID, state: String = "idle", of parent: HostSession, on link: AgentLink, in core: HostCore
    ) throws {
        let line = Data(
            #"{"params":{"sessionId":"parent","update":{"sessionUpdate":"subagent_update","sessionId":"\#(id.rawValue)","state":{"state":"\#(state)"}}}}"#
                .utf8)
        let announcement = try #require(AgentUpdate.parse(line))
        core.apply(announcement.update, to: parent, on: link)
    }

}
