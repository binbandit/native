import Foundation
import Testing

@testable import ACP

@Suite struct CompactionTests {
    @Test func completedCompactionInvalidatesEarlierUsage() throws {
        var state = SessionState()
        for line in Wire.codexAutomaticCompaction.dropLast() {
            state.apply(try Wire.update(line))
        }
        #expect(state.usage == nil)
        #expect(state.contextCompactedAt != nil)
        guard case .toolCall(let call)? = state.items.last else {
            Issue.record("Missing compaction operation")
            return
        }
        #expect(call.title == "Compact conversation")
        #expect(call.status == .completed)
    }

    @Test func nextUsageRestoresTheSmallerCount() throws {
        var state = SessionState()
        for line in Wire.codexAutomaticCompaction { state.apply(try Wire.update(line)) }
        #expect(state.usage?.used == 19_339)
        #expect(state.usage?.size == 258_400)
        // Claude can enrich a terminal event after it has already reported fresh usage.
        state.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"completed"}"#))
        #expect(state.usage?.used == 19_339)
    }

    @Test(arguments: ["in_progress", "failed", "cancelled", "future_status"])
    func unsuccessfulCompactionKeepsTheCount(status: String) throws {
        var state = SessionState()
        state.apply(try usage(used: 22_519))
        state.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"\#(status)"}"#))
        #expect(state.usage?.used == 22_519)
        #expect(state.contextCompactedAt == nil)
    }

    @Test func zeroPlaceholderWaitsForTheNextCountAndRetainsMetadata() throws {
        var state = SessionState()
        state.apply(
            try update(
                #"{"sessionUpdate":"usage_update","used":80000,"size":200000,"cost":{"amount":0.19,"currency":"USD"},"_meta":{"_claude/model":"fixture-model"}}"#
            ))
        state.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"completed"}"#))
        state.apply(try usage(used: 0))
        #expect(state.usage == nil)
        state.apply(try usage(used: 12_000))
        #expect(state.usage?.used == 12_000)
        #expect(state.usage?.cost?.amount == 0.19)
        #expect(state.usage?.model == "fixture-model")
    }

    @Test func anotherCompactionInvalidatesTheNewCount() throws {
        var state = SessionState()
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        state.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"completed"}"#),
            at: first)
        state.apply(try usage(used: 12_000))
        state.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-2","status":"completed"}"#),
            at: second)
        #expect(state.usage == nil)
        #expect(state.contextCompactedAt == second)
    }

    @Test func streamedAndFinalSummariesShareOneTranscriptOperation() throws {
        var state = SessionState()
        state.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"in_progress"}"#))
        state.apply(
            try update(
                #"{"sessionUpdate":"compaction_summary_chunk","compactionId":"compact-1","content":{"type":"text","text":"Remember "}}"#
            ))
        state.apply(
            try update(
                #"{"sessionUpdate":"compaction_summary_chunk","compactionId":"compact-1","content":{"type":"text","text":"amber"}}"#
            ))
        guard case .toolCall(let streamed)? = state.items.last else {
            Issue.record("Missing streamed summary")
            return
        }
        #expect(streamed.content == [.content(.text("Remember amber"))])
        state.apply(
            try update(
                #"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"completed","summary":[{"type":"text","text":"Remember amber."}]}"#
            ))
        #expect(state.items.count == 1)
        guard case .toolCall(let finished)? = state.items.last else { return }
        #expect(finished.content == [.content(.text("Remember amber."))])
        #expect(finished.status == .completed)
    }

    @Test func steeringWaitsForCompactionToFinish() throws {
        var gate = SteeringGate()
        gate.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"in_progress"}"#))
        #expect(gate.delivery(supportsSteering: true) == .waitForTool("Compact conversation"))
        gate.apply(
            try update(#"{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"completed"}"#))
        #expect(gate.delivery(supportsSteering: true) == .steer)
    }

    private func usage(used: Int) throws -> SessionUpdate {
        try update(#"{"sessionUpdate":"usage_update","used":\#(used),"size":200000}"#)
    }

    private func update(_ json: String) throws -> SessionUpdate {
        try Wire.update(
            #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"fixture","update":\#(json)}}"#)
    }
}
