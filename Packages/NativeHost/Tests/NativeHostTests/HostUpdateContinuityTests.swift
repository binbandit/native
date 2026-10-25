import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

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
