import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite("Tool-safe steering", .serialized, .timeLimit(.minutes(1)))
struct HostSteeringTests {
    @Test func holdsSteerUntilToolFinishes() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(session.id)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "tool-sleep"))
        try await recorder.wait("the command to start") {
            await $0.mirror(session.id).state.items.contains {
                if case .toolCall = $0 { true } else { false }
            }
        }
        _ = try await recorder.client.prompt(
            PromptParams(sessionID: session.id, text: "after sleep", behavior: .steer))
        try await recorder.wait("the steer to arrive") { _ in harness.received.contains("steer\tafter sleep") }
        #expect(harness.received == ["prompt\ttool-sleep", "tool-finished\tsleep", "steer\tafter sleep"])
        await recorder.stop()
    }
    @Test func heldSteerCanBeEditedOrRemoved() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(session.id)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "tool-sleep"))
        try await recorder.wait("the command") {
            await $0.mirror(session.id).state.items.contains { if case .toolCall = $0 { true } else { false } }
        }
        let edited = PromptParams(sessionID: session.id, text: "original", behavior: .steer)
        let removed = PromptParams(sessionID: session.id, text: "remove me", behavior: .steer)
        #expect(try await recorder.client.prompt(edited) == .queued)
        #expect(try await recorder.client.prompt(removed) == .queued)
        #expect(await recorder.listed(session.id)?.queue.first?.waitingForTool == "sleep 20")
        try await recorder.client.updateQueued(
            QueueItemParams(sessionID: session.id, itemID: edited.requestID, text: "edited"))
        try await recorder.client.removeQueued(QueueItemParams(sessionID: session.id, itemID: removed.requestID))
        try await recorder.wait("the edited steer") { _ in harness.received.contains("steer\tedited") }
        #expect(harness.received == ["prompt\ttool-sleep", "tool-finished\tsleep", "steer\tedited"])
        await recorder.stop()
    }

    @Test func adapterWithoutSteeringIsInterruptedOnlyAfterItsTool() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment["FAKE_AGENT_NO_STEERING"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(session.id)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "tool-sleep"))
        try await recorder.wait("the command") {
            await $0.mirror(session.id).state.items.contains { if case .toolCall = $0 { true } else { false } }
        }
        #expect(
            try await recorder.client.prompt(
                PromptParams(sessionID: session.id, text: "next step", behavior: .steer)) == .queued)
        try await recorder.wait("both turns") { await $0.turnsEnded(session.id).count == 2 }
        #expect(await recorder.turnsEnded(session.id) == ["cancelled", "end_turn"])
        #expect(harness.received == ["prompt\ttool-sleep", "tool-finished\tsleep", "prompt\tnext step"])
        #expect(await recorder.listed(session.id)?.isQueuePaused == false)
        await recorder.stop()
    }

    @Test func stopStillCancelsImmediatelyAndHoldsTheSteer() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(session.id)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "tool-sleep"))
        try await recorder.wait("the command") {
            await $0.mirror(session.id).state.items.contains { if case .toolCall = $0 { true } else { false } }
        }
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "held", behavior: .steer))
        try await recorder.client.cancel(session.id)
        // Existing Stop reports an unverified command lifetime as an error, even after ACP acknowledges.
        try await recorder.wait("the stopped turn") { await $0.turnsEnded(session.id) == ["error"] }
        #expect(!harness.received.contains("tool-finished\tsleep"))
        #expect(!harness.received.contains("steer\theld"))
        #expect(await recorder.listed(session.id)?.queue.map(\.text) == ["held"])
        #expect(await recorder.listed(session.id)?.isQueuePaused == true)
        await recorder.stop()
    }

    @Test func nonInterruptingPluginDeliversDuringTheTool() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.steeringPolicy = .nonInterrupting
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(session.id)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "tool-sleep"))
        try await recorder.wait("the command") {
            await $0.mirror(session.id).state.items.contains { if case .toolCall = $0 { true } else { false } }
        }
        #expect(
            try await recorder.client.prompt(
                PromptParams(sessionID: session.id, text: "immediate", behavior: .steer)) == .steered)
        #expect(harness.received == ["prompt\ttool-sleep", "steer\timmediate"])
        try await recorder.wait("the tool to finish") { _ in harness.received.contains("tool-finished\tsleep") }
        await recorder.stop()
    }

    @Test func heldSteerSurvivesHostRestartOnce() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let first = try await harness.connect()
        let session = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await first.client.attach(session.id)
        _ = try await first.client.prompt(PromptParams(sessionID: session.id, text: "tool-sleep"))
        try await first.wait("the command") {
            await $0.mirror(session.id).state.items.contains { if case .toolCall = $0 { true } else { false } }
        }
        _ = try await first.client.prompt(PromptParams(sessionID: session.id, text: "survives", behavior: .steer))
        harness.kill()
        await first.stop()
        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(session.id)
        try await second.wait("recovery and the held message") { await $0.turnsEnded(session.id).count == 2 }
        #expect(harness.received.filter { $0 == "prompt\tsurvives" || $0 == "steer\tsurvives" }.count == 1)
        await second.stop()
    }

    @Test func queuedTurnWaitsForTheSteeringAcknowledgement() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        harness.agentEnvironment["FAKE_AGENT_DELAY_STEER"] = "1"
        try harness.start()
        let recorder = try await harness.connect()
        let session = try await recorder.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false)))
        try await recorder.client.attach(session.id)
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "tool-sleep"))
        try await recorder.wait("the command") {
            await $0.mirror(session.id).state.items.contains { if case .toolCall = $0 { true } else { false } }
        }
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "next"))
        _ = try await recorder.client.prompt(PromptParams(sessionID: session.id, text: "after sleep", behavior: .steer))
        try await recorder.wait("the acknowledgement and queued turn") {
            let ended = await $0.turnsEnded(session.id).count == 2
            return ended && harness.received.contains("steer-accepted\tafter sleep")
        }
        #expect(
            harness.received == [
                "prompt\ttool-sleep", "tool-finished\tsleep", "steer\tafter sleep", "steer-accepted\tafter sleep",
                "prompt\tnext",
            ])
        await recorder.stop()
    }

}
