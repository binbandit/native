import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// The host as users depend on it: a real `native-host` process and a scripted ACP agent, broken on
/// purpose. Every test kills something mid-turn and checks that the work finishes anyway, and that
/// the transcript says what happened.
@Suite("Durable host, end to end", .serialized, .timeLimit(.minutes(1)))
struct HostEndToEndTests {
    private func startSession(_ recorder: Recorder, harness: HostHarness) async throws -> HostSessionID {
        let summary = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(summary.id)
        return summary.id
    }

    @Test("A prompt runs through the host and its reply streams back")
    func promptRoundTrip() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        let delivery = try await recorder.client.prompt(PromptParams(sessionID: session, text: "hello"))
        #expect(delivery == .prompted)
        try await recorder.wait("the turn to end") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await recorder.mirror(session).userMessages == ["hello"])
        #expect(await recorder.agentText(session) == "echo: hello")
        await recorder.stop()
    }

    @Test("The turn keeps going with no client attached, and a new client sees it finished")
    func survivesTheClientQuitting() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let session = try await startSession(first, harness: harness)
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "slow 5"))
        await first.stop()

        try await Task.sleep(for: .seconds(2.5))
        let second = try await harness.connect()
        try await second.client.attach(session)
        try await second.wait("the replayed turn end") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await second.agentText(session).contains("tick 5"))
        await second.stop()
    }

    @Test("A prompt sent twice with one request id is delivered once")
    func idempotentPrompts() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        let request = PromptParams(sessionID: session, text: "only once")
        #expect(try await recorder.client.prompt(request) == .prompted)
        #expect(try await recorder.client.prompt(request) == .prompted)
        try await recorder.wait("the turn to end") { await $0.turnsEnded(session).count == 1 }
        try await Task.sleep(for: .milliseconds(300))
        #expect(harness.received == ["prompt\tonly once"])
        await recorder.stop()
    }

    @Test("Killing the host mid-turn: the new host reloads the session and tells the agent to continue")
    func hostKilledMidTurn() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let session = try await startSession(first, harness: harness)
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "slow 30"))
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "queued after"))
        try await first.wait("the turn to get going") { await $0.agentText(session).contains("tick 2") }
        harness.kill()
        await first.stop()

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session)
        try await second.wait("the resumed turn and the queued message to finish", timeout: .seconds(30)) {
            await $0.turnsEnded(session).count == 2
        }
        let recovery = try #require(await second.recoveries(session).first)
        #expect(recovery.cause == .hostStopped)
        #expect(recovery.action == .resumed)
        let received = harness.received
        #expect(received.first == "prompt\tslow 30")
        #expect(received.dropFirst().first?.hasPrefix("prompt\t[Native] Your previous turn was interrupted") == true)
        #expect(received.last == "prompt\tqueued after")
        #expect(await second.agentText(session).contains("echo: queued after"))
        let activity = try await second.client.activity()
        #expect(activity.contains { $0.kind == .recovered && $0.recovery?.action == .resumed })
        await second.stop()
    }

    @Test("A prompt that never reached the agent is sent again after the host dies")
    func lostPromptIsResent() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let session = try await startSession(first, harness: harness)
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "lose-once please"))
        try await first.wait("the agent to get it") { _ in harness.received.count == 1 }
        harness.kill()
        await first.stop()

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session)
        try await second.wait("the resent turn to end", timeout: .seconds(30)) {
            await $0.turnsEnded(session) == ["end_turn"]
        }
        #expect(await second.recoveries(session).map(\.action) == [.resent])
        #expect(harness.received == ["prompt\tlose-once please", "prompt\tlose-once please"])
        #expect(await second.agentText(session).contains("echo: lose-once please"))
        await second.stop()
    }

    @Test("An agent that crashes mid-turn is restarted and resumes, and the user is told")
    func agentCrashMidTurn() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "crash-once now"))
        try await recorder.wait("recovery to finish the turn", timeout: .seconds(30)) {
            await $0.turnsEnded(session) == ["end_turn"]
        }
        let recovery = try #require(await recorder.recoveries(session).first)
        #expect(recovery.cause == .agentStopped)
        #expect(recovery.action == .resumed)
        #expect(await recorder.agentText(session).contains("resumed"))
        let notices = await recorder.mirror(session).state.items.compactMap { item in
            if case .notice(let notice) = item { notice.text } else { nil }
        }
        #expect(notices.contains { $0.hasPrefix("Fake Agent stopped unexpectedly") })
        await recorder.stop()
    }

    @Test("Permission requests reach the client and the answer reaches the agent")
    func permissions() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "permission please"))
        try await recorder.wait("the approval request") { await !$0.mirror(session).state.pendingPermissions.isEmpty }
        let toolCall = try #require(await recorder.mirror(session).state.pendingPermissions.first?.toolCallID)
        let summary = try await recorder.client.sessions().first { $0.id == session }
        #expect(summary?.needsApproval == true)
        try await recorder.client.respondPermission(
            RespondPermissionParams(sessionID: session, toolCallID: toolCall, optionID: "allow"))
        try await recorder.wait("the turn to end") { await $0.turnsEnded(session) == ["end_turn"] }
        #expect(await recorder.agentText(session).contains("permission: allow"))
        await recorder.stop()
    }

    @Test("Messages sent while a turn runs are queued, and steering joins the running turn")
    func queueAndSteer() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "slow 6"))
        #expect(
            try await recorder.client.prompt(PromptParams(sessionID: session, text: "next", behavior: .queue))
                == .queued)
        #expect(
            try await recorder.client.prompt(PromptParams(sessionID: session, text: "also this", behavior: .steer))
                == .steered)
        try await recorder.wait("both turns to end", timeout: .seconds(20)) { await $0.turnsEnded(session).count == 2 }
        #expect(harness.received == ["prompt\tslow 6", "steer\talso this", "prompt\tnext"])
        await recorder.stop()
    }

    @Test("Restart Host Now exits for the new binary, which resumes the turn as an update")
    func restartNow() async throws {
        let harness = try HostHarness()
        try harness.start()
        let first = try await harness.connect()
        let session = try await startSession(first, harness: harness)
        _ = try await first.client.prompt(PromptParams(sessionID: session, text: "slow 20"))
        try await first.wait("the turn to get going") { await $0.agentText(session).contains("tick 2") }
        try await first.client.shutdownHost(stopAgents: false, immediately: true)
        // 75 is what launchd restarts on; the harness plays launchd.
        #expect(harness.waitForExit() == 75)
        await first.stop()

        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session)
        try await second.wait("the resumed turn to finish", timeout: .seconds(30)) {
            await $0.turnsEnded(session).count == 1
        }
        let recovery = try #require(await second.recoveries(session).first)
        #expect(recovery.cause == .hostUpdated)
        #expect(recovery.action == .resumed)
        await second.stop()
    }

    @Test("Restarting once idle waits for the running turn to end")
    func restartWhenIdle() async throws {
        let harness = try HostHarness()
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await startSession(recorder, harness: harness)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session, text: "slow 4"))
        try await recorder.client.shutdownHost(stopAgents: false)
        #expect(harness.waitForExit() == 75)
        #expect(await recorder.turnsEnded(session) == ["end_turn"])
        await recorder.stop()
    }
}
