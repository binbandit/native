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
}
