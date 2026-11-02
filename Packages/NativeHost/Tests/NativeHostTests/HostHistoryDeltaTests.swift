import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

/// Switching back: a conversation the task returns to is sent what it missed, chosen by the budgeted
/// handoff, with its next message. Through a real host and the fake agent, reading what it received.
@Suite("Task history deltas in the host", .serialized, .timeLimit(.minutes(1)))
struct HostHistoryDeltaTests {
    /// The first conversation answered "one", then a change of agent joined the second, which
    /// answered "two" (items 4 to 6); now the task returns to the first.
    private func returning(_ recorder: Recorder) async throws -> (first: HostSessionSummary, second: HostSessionSummary)
    {
        let first = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "one"))
        try await recorder.wait("the first turn") { await $0.turnsEnded(first.id).count == 1 }
        let second = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await join(recorder, second, after: first, conveyed: [1...3])
        _ = try await recorder.client.prompt(PromptParams(sessionID: second.id, text: "two"))
        try await recorder.wait("the second turn") { await $0.turnsEnded(second.id).count == 1 }
        return (first, second)
    }

    private func join(
        _ recorder: Recorder, _ target: HostSessionSummary, after source: HostSessionSummary,
        conveyed: [ClosedRange<Int>] = []
    ) async throws -> TaskHistorySummary {
        try await recorder.client.joinHistory(
            JoinHistoryParams(
                sessionID: target.id, sourceAgentID: source.agentID,
                sourceAgentSessionID: try #require(source.agentSessionID), conveyed: conveyed))
    }

    /// The prompts the fake agent received, each on one line.
    private func prompts(_ harness: HostHarness) -> [String] {
        harness.received.filter { $0.hasPrefix("prompt\t") }
    }

    @Test("A returning conversation gets only what it missed with its next message, and then has seen it all")
    func returnsWithDelta() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await returning(recorder)
        let prepared = try await join(recorder, first, after: second)
        #expect(prepared.current == 1)
        #expect(prepared.transfers.filter { $0.strategy == .delta }.map(\.state) == [.prepared])
        // A retried join prepares nothing more.
        #expect(try await join(recorder, first, after: second).transfers.count == prepared.transfers.count)

        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "three"))
        try await recorder.wait("the return") { await $0.turnsEnded(first.id).count == 2 }
        let sent = try #require(prompts(harness).last)
        #expect(sent.contains("<native_instructions id=\"task-history:"))
        #expect(sent.contains("item=history/4") && sent.contains("item=history/5"))
        #expect(sent.contains("echo: two"))
        // What it already had (its own turn) isn't sent again.
        #expect(!sent.contains("item=history/1") && !sent.contains("item=history/2"))
        #expect(sent.hasSuffix("three"))

        let summary = try await recorder.client.historySummary(of: first.id)
        let delta = try #require(summary.transfers.first { $0.strategy == .delta })
        #expect(delta.state == .delivered)
        #expect(delta.conveyed == [4...6])
        #expect(summary.participants.first?.seen == summary.head)
        #expect(try await recorder.client.missingHistory(of: first.id).items.isEmpty)
        // Its frame carries the transfer's own marker, so a transcript finds what it covered.
        #expect(sent.contains("id=\"\(delta.markerID)\""))
        await recorder.stop()
    }

    @Test("Undoing a return withdraws its context: the next message goes alone")
    func withdrawn() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await returning(recorder)
        _ = try await join(recorder, first, after: second)
        let withdrawn = try await recorder.client.withdrawHistory(of: first.id)
        #expect(withdrawn.transfers.filter { $0.strategy == .delta }.map(\.state) == [.superseded])
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "three"))
        try await recorder.wait("the next turn") { await $0.turnsEnded(first.id).count == 2 }
        #expect(prompts(harness).last == "prompt\tthree")
        // It still hasn't seen the other conversation's turn.
        #expect(try await recorder.client.missingHistory(of: first.id).items.map(\.seq) == [4, 5, 6])
        await recorder.stop()
    }

    @Test("A delta stopped before the agent answered goes with the next message instead")
    func stoppedDelta() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await returning(recorder)
        _ = try await join(recorder, first, after: second)
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "silent-until-stopped"))
        try await recorder.wait("the agent to get the message") { _ in
            harness.received.contains { $0.hasSuffix("silent-until-stopped") }
        }
        try await recorder.client.cancel(first.id)
        try await recorder.wait("the stop") { await $0.turnsEnded(first.id).count == 2 }
        // The stopped attempt gives way to a fresh delta, chosen again for the next message.
        let stopped = try await recorder.client.historySummary(of: first.id)
        #expect(stopped.transfers.filter { $0.strategy == .delta }.map(\.state) == [.superseded, .prepared])

        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "three"))
        try await recorder.wait("the next turn") { await $0.turnsEnded(first.id).count == 3 }
        let sent = try #require(prompts(harness).last)
        #expect(sent.contains("item=history/5") && sent.hasSuffix("three"))
        let delivered = try await recorder.client.historySummary(of: first.id)
        #expect(delivered.transfers.filter { $0.strategy == .delta }.map(\.state) == [.superseded, .delivered])
        await recorder.stop()
    }

    @Test("Recovery credits a delta only when the replay shows its frame, not an older message's text")
    func recoveryNeedsTheFrame() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let first = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        // An older message whose text contains the one that will be lost.
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "about lose-once go"))
        try await recorder.wait("the first turn") { await $0.turnsEnded(first.id).count == 1 }
        let second = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await join(recorder, second, after: first, conveyed: [1...3])
        _ = try await recorder.client.prompt(PromptParams(sessionID: second.id, text: "two"))
        try await recorder.wait("the second turn") { await $0.turnsEnded(second.id).count == 1 }
        _ = try await join(recorder, first, after: second)
        // The agent never records this one: the host stops before it answers.
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "lose-once go"))
        // It goes with the delta, so it ends after the frame.
        try await recorder.wait("the lost message") { _ in
            harness.received.contains { $0.hasSuffix("</native_instructions>lose-once go") }
        }
        await recorder.stop()
        harness.kill()

        try harness.start()
        let restarted = try await harness.connect()
        // Recovery takes the older message for this one and resumes; the delta goes with that.
        try await restarted.wait("the recovered turn") { _ in
            harness.received.filter { $0.hasPrefix("prompt\t") }.count == 4
        }
        let resumed = try #require(harness.received.filter { $0.hasPrefix("prompt\t") }.last)
        #expect(resumed.contains("task-history:") && resumed.contains("item=history/5"))
        try await restarted.wait("the delta delivered with it") {
            (try? await $0.client.historySummary(of: first.id))?.transfers.contains {
                $0.strategy == .delta && $0.state == .delivered
            } == true
        }
        await restarted.stop()
    }

    @Test("A replayed earlier attempt never vouches for context chosen again after it")
    func freshMarkerAfterStop() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let (first, second) = try await returning(recorder)
        _ = try await join(recorder, first, after: second)
        // The agent records this attempt and its frame, then it's stopped before any answer.
        _ = try await recorder.client.prompt(
            PromptParams(sessionID: first.id, text: "silent-until-stopped lose-once go"))
        try await recorder.wait("the agent to get the attempt") { _ in
            harness.received.contains { $0.hasSuffix("silent-until-stopped lose-once go") }
        }
        try await recorder.client.cancel(first.id)
        try await recorder.wait("the stop") { await $0.turnsEnded(first.id).count == 2 }
        // More happens elsewhere, then a message the agent never records, cut off by a host stop.
        _ = try await recorder.client.prompt(PromptParams(sessionID: second.id, text: "more"))
        try await recorder.wait("more work") { await $0.turnsEnded(second.id).count == 2 }
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "lose-once go"))
        try await recorder.wait("the lost message") { _ in
            harness.received.contains { $0.hasSuffix("</native_instructions>lose-once go") }
        }
        await recorder.stop()
        harness.kill()

        try harness.start()
        let restarted = try await harness.connect()
        // Recovery takes the earlier attempt for the lost message; its frame isn't this context's.
        try await restarted.wait("the delta delivered with the recovery") {
            (try? await $0.client.historySummary(of: first.id))?.transfers.contains {
                $0.strategy == .delta && $0.state == .delivered
            } == true
        }
        let resumed = try #require(harness.received.filter { $0.hasPrefix("prompt\t") }.last)
        #expect(resumed.contains("echo: more"))
        let deltas = try await restarted.client.historySummary(of: first.id).transfers.filter { $0.strategy == .delta }
        #expect(deltas.map(\.state) == [.superseded, .superseded, .delivered])
        #expect(Set(deltas.map(\.markerID)).count == 3)
        await restarted.stop()
    }

    @Test("A client handoff whose receipt names history items credits what it carried, not what it left out")
    func handoffReceipt() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let first = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        _ = try await recorder.client.prompt(PromptParams(sessionID: first.id, text: "one"))
        try await recorder.wait("the first turn") { await $0.turnsEnded(first.id).count == 1 }
        let second = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: "/tmp", attach: true))
        let joined = try await join(recorder, second, after: first)
        // The client chose from the history: it carried the reply, and its budget left out the message.
        let items = try await recorder.client.readHistory(ReadHistoryParams(sessionID: first.id))
        var transfer = ContextTransfer(
            draft: TaskHistoryDelta.draft(items, participants: joined.participants),
            destination: .init(agent: "fake", session: try #require(second.agentSessionID)), model: nil,
            plan: AgentTransitionPlan.resolve(.freshConversation, target: .init(negotiated: nil)),
            budget: .init(windowTokens: 200_000))
        transfer.receipt.included.removeAll { $0.position == 1 }
        _ = try await recorder.client.prompt(PromptParams(sessionID: second.id, text: "two"))
        _ = try await recorder.client.recordHandoff(
            HandoffHistoryParams(sessionID: second.id, receipt: transfer.receipt))
        try await recorder.wait("the second turn") { await $0.turnsEnded(second.id).count == 1 }
        let summary = try await recorder.client.historySummary(of: second.id)
        #expect(summary.transfers.first?.conveyed == [2...3])
        // Item 1 stays missing, so its watermark stops before it.
        #expect(summary.participants.map(\.seen) == [3, 0])
        #expect(try await recorder.client.missingHistory(of: second.id).items.map(\.seq) == [1])
        await recorder.stop()
    }
}
