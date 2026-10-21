import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// The playtest's repros through a real host and the fake agent: what the transcript says once a turn
/// ends, is retried, or is stopped and the agent keeps going.
@Suite("Host turn endings, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostTurnEndingTests {
    private func started(_ harness: HostHarness) async throws -> (Recorder, HostSessionID) {
        try harness.start()
        let recorder = try await harness.connect()
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true))
        return (recorder, summary.id)
    }

    private func calls(_ mirror: SessionMirror) -> [ToolCallState] {
        mirror.state.items.compactMap { item in
            if case .toolCall(let call) = item { call } else { nil }
        }
    }

    private func notices(_ mirror: SessionMirror) -> [TranscriptNotice] {
        mirror.state.items.compactMap { item in
            if case .notice(let notice) = item { notice } else { nil }
        }
    }

    @Test("An approved call the agent never closes stops running when the turn ends")
    func approvedCallSettles() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "permission"))
        try await recorder.wait("the approval") { await !$0.mirror(session).state.pendingPermissions.isEmpty }
        let toolCall = try #require(await recorder.mirror(session).state.pendingPermissions.first?.toolCallID)
        try await recorder.client.respondPermission(
            RespondPermissionParams(sessionID: session, toolCallID: toolCall, optionID: "allow"))
        try await recorder.wait("the turn") { await $0.turnsEnded(session) == ["end_turn"] }

        let call = try #require(calls(await recorder.mirror(session)).first)
        #expect(call.status == .unreported)
        #expect(call.finishedAt != nil)
        await recorder.stop()
    }

    @Test("A retry that went through says so, in the place it promised it")
    func retryNoticeSettles() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "flaky-once hi"))
        try await recorder.wait("the failure") { await !$0.failures(session).isEmpty }
        let waiting = try #require(notices(await recorder.mirror(session)).first)
        #expect(waiting.isError)
        #expect(await recorder.mirror(session).state.turns.last?.stopReason == nil)

        try await recorder.wait("the retry", timeout: .seconds(15)) {
            await $0.turnsEnded(session).contains("end_turn")
        }
        let mirror = await recorder.mirror(session)
        #expect(notices(mirror).map(\.text) == ["Reconnected to Fake Agent, and your message went through on retry."])
        #expect(notices(mirror).first?.id == waiting.id)
        #expect(notices(mirror).first?.isError == false)
        #expect(mirror.state.turns.count == 1)
        #expect(mirror.state.turns.last?.stopReason == .endTurn)
        await recorder.stop()
    }

    @Test("A stubborn agent cannot send more output after Native verifies its stop")
    func lateOutputAfterStop() async throws {
        let harness = try HostHarness()
        let (recorder, session) = try await started(harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "stubborn 12"))
        try await recorder.wait("the turn to get going") { await $0.agentText(session).contains("tick 1") }
        try await recorder.client.cancel(session)
        try await recorder.wait("the stop to show") { await $0.summaries[session]?.isStopping == true }
        try await Task.sleep(for: .milliseconds(1_100))
        try await recorder.client.cancel(session)
        try await recorder.wait("the turn to end") { await $0.turnsEnded(session) == ["cancelled"] }
        let stoppedText = await recorder.agentText(session)
        try await Task.sleep(for: .seconds(3))

        let mirror = await recorder.mirror(session)
        #expect(mirror.state.turns.map(\.isLateOutput) == [false])
        #expect(await recorder.agentText(session) == stoppedText)
        await recorder.stop()
    }
}
