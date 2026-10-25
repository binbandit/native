import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

/// An update asks the host to restart once idle (`_native/host/shutdown {stopAgents: false}`); it
/// must never cut off work to do it (docs/durability.md, "Updates").
@Suite("Updates wait for work in progress", .serialized, .timeLimit(.minutes(1)))
struct HostUpdateContinuityTests {
    private func startSession(_ recorder: Recorder, harness: HostHarness) async throws -> HostSessionID {
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(summary.id)
        return summary.id
    }

    @Test("A running host reads as running, so a launch that finds it slow to answer never restarts it")
    func runningHost() async throws {
        let harness = try HostHarness()
        #expect(!harness.location.isHostRunning)
        try harness.start()
        let recorder = try await harness.connect()
        #expect(harness.location.isHostRunning)
        await recorder.stop()
        harness.kill()
        #expect(!harness.location.isHostRunning)
    }

    @Test("An update waits for a hidden command, and its reply arrives before the host restarts")
    func hiddenCommand() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        let command = Task {
            try await recorder.client.runHidden(RunHiddenParams(sessionID: session, text: "slow 8"))
        }
        try await recorder.wait("the hidden command") { await $0.summaries[session]?.isRunningHiddenCommand == true }
        try await recorder.client.shutdownHost(stopAgents: false)
        #expect(try await harness.waitForExit(timeout: .milliseconds(500)) == nil)
        #expect(try await command.value.contains("tick 8"))
        #expect(try await harness.waitForExit() == 75)
        await recorder.stop()
    }

    @Test("An update waits for a retry to go out and be answered")
    func pendingRetry() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "flaky-once hi"))
        try await recorder.wait("the retry to be scheduled") { await $0.summaries[session]?.retryAt != nil }
        try await recorder.client.shutdownHost(stopAgents: false)
        #expect(try await harness.waitForExit(timeout: .seconds(1)) == nil)
        #expect(try await harness.waitForExit() == 75)
        #expect(await recorder.turnsEnded(session) == ["end_turn"])
        #expect(harness.received == ["prompt\tflaky-once hi", "prompt\tflaky-once hi"])
        await recorder.stop()
    }

    @Test("A subagent working in the background holds an update while its agent runs, and not after")
    @HostActor
    func backgroundSubagent() async throws {
        let host = try await ExecHost.make()
        let core = host.core
        defer { for link in core.agents.values { link.endNow() } }
        let recorder = Recorder(client: host.owner)
        await recorder.listen()
        try await host.owner.syncAgents([host.harness.agentSpec])
        let summary = try await host.owner.newSession(
            NewSessionParams(agentID: "fake", cwd: host.projectPath, attach: true))
        _ = try await host.owner.prompt(PromptParams(sessionID: summary.id, text: "hello"))
        try await recorder.wait("the turn") { await $0.turnsEnded(summary.id) == ["end_turn"] }
        let parent = try #require(core.sessions[summary.id])
        let link = try #require(core.agents["fake"])
        #expect(!parent.holdsRestart)

        let running = Data(
            #"{"params":{"sessionId":"parent","update":{"sessionUpdate":"subagent_update","sessionId":"child","state":{"state":"running"}}}}"#
                .utf8)
        core.apply(try #require(AgentUpdate.parse(running)).update, to: parent, on: link)
        #expect(parent.holdsRestart)
        try await recorder.wait("the app to hear of it") { await $0.summaries[summary.id]?.holdsRestart == true }

        // Its agent's process goes away: the transcript's last word on the child is history now.
        let generation = link.generation
        link.end()
        core.agentExited("fake", generation: generation)
        #expect(!parent.holdsRestart)
        try await recorder.wait("the app to hear of it") { await $0.summaries[summary.id]?.holdsRestart == false }

        // A quiet reload keeps the session looking idle, but the summary still says it holds.
        parent.loading = Task {}
        #expect(parent.summary.phase == .idle)
        #expect(parent.summary.holdsRestart)
        parent.loading = nil
        await host.stop()
    }

    @Test("The app counts what the host waits for, and judges a host that doesn't report it by its summary")
    func summaryHoldsRestart() throws {
        func summary(
            _ phase: HostSessionPhase = .idle, hidden: Bool = false, reported: Bool? = nil
        )
            -> HostSessionSummary
        {
            HostSessionSummary(
                id: HostSessionID(), agentID: "fake", agentName: "Fake Agent", agentSessionID: nil, cwd: "/tmp",
                phase: phase, isRunningHiddenCommand: hidden, isHoldingRestart: reported)
        }
        // What the host reports wins: a quiet reload or background work looks idle otherwise.
        #expect(summary(reported: true).holdsRestart)
        #expect(!summary(.prompting, reported: false).holdsRestart)
        // An older host's summary says enough for the rest.
        #expect(!summary().holdsRestart)
        #expect(summary(.prompting).holdsRestart)
        #expect(summary(hidden: true).holdsRestart)
        #expect(summary(.loading).holdsRestart)

        let encoded = try JSONEncoder().encode(summary(.prompting, reported: true))
        var fields = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields["isHoldingRestart"] = nil
        let older = try JSONDecoder().decode(
            HostSessionSummary.self, from: try JSONSerialization.data(withJSONObject: fields))
        #expect(older.isHoldingRestart == nil)
        #expect(older.holdsRestart)
    }

    @Test("After the app reconnects, an update waits for a running turn and an approval without interrupting them")
    func reconnectWithApproval() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let running = try await startSession(first, harness: harness)
        let approval = try await startSession(first, harness: harness)
        _ = try await first.client.prompt(PromptParams(sessionID: running, text: "slow 8"))
        _ = try await first.client.prompt(PromptParams(sessionID: approval, text: "permission please"))
        try await first.wait("the approval") { await $0.summaries[approval]?.needsApproval == true }
        let before = try #require(await first.client.hostInfo)
        // The app quits for the update; the new one connects to the same host process.
        await first.stop()

        let reopened = try await harness.connect()
        #expect(await reopened.client.hostInfo?.epoch == before.epoch)
        try await reopened.client.attach(running)
        try await reopened.client.attach(approval)
        let tool = try #require(await reopened.mirror(approval).state.pendingPermissions.first?.toolCallID)
        try await reopened.client.shutdownHost(stopAgents: false)
        try await reopened.wait("the running turn to finish") { await $0.turnsEnded(running) == ["end_turn"] }
        #expect(try await harness.waitForExit(timeout: .milliseconds(500)) == nil)
        #expect(await reopened.recoveries(running).isEmpty)
        #expect(await reopened.failures(running).isEmpty)
        try await reopened.client.respondPermission(
            RespondPermissionParams(sessionID: approval, toolCallID: tool, optionID: "allow"))
        #expect(try await harness.waitForExit() == 75)
        #expect(await reopened.turnsEnded(approval) == ["end_turn"])
        await reopened.stop()
    }
}
