import Foundation
import Testing

@testable import ACP

/// What a returning agent session is told: the budgeted handoff's selection over the history items it
/// missed, and which of them that delivery covers.
struct TaskHistoryDeltaTests {
    private let participants = [
        TaskHistoryParticipant(ordinal: 1, agentID: "claude-code", agentSessionID: SessionID("c1")),
        TaskHistoryParticipant(ordinal: 2, agentID: "codex", agentSessionID: SessionID("x1")),
    ]

    /// Codex's turn while Claude Code was away: a message, reasoning, a command and a long reply.
    private let missed: [TaskHistoryItem] = [
        TaskHistoryItem(seq: 4, source: 2, body: .user(.init(text: "now fix the iOS build", attachments: ["log.txt"]))),
        TaskHistoryItem(seq: 5, source: 2, body: .thought("the target is missing a file")),
        TaskHistoryItem(
            seq: 6, source: 2,
            body: .tool(.init(id: "c1", title: "xcodebuild", kind: "execute", status: "completed", input: "xcodebuild"))
        ),
        TaskHistoryItem(
            seq: 7, source: 2, body: .agent(String(repeating: "Added the file to the target. ", count: 80))),
        TaskHistoryItem(seq: 8, source: 2, body: .turnEnded(stopReason: "end_turn")),
    ]

    private func transfer(window: Int) -> ContextTransfer {
        ContextTransfer(
            draft: TaskHistoryDelta.draft(missed, participants: participants),
            destination: .init(agent: "claude-code", session: SessionID("c1")), model: nil,
            plan: AgentTransitionPlan.resolve(.reuse, target: .init(negotiated: nil), sameSession: true),
            budget: .init(windowTokens: window))
    }

    @Test("Messages go as text, under the agent that produced them; reasoning and tools say they stay out")
    func draft() {
        let draft = TaskHistoryDelta.draft(missed, participants: participants)
        #expect(draft.items.map(\.reference.kind) == [.user, .agent])
        #expect(draft.items.map(\.reference.position) == [4, 7])
        #expect(draft.items.allSatisfy { $0.reference.source.agent == "codex" })
        #expect(
            Set(draft.omitted.map(\.reason)) == [.attachmentNotReplayed, .reasoning, .toolState])
    }

    @Test("A delivered delta covers what it carried and what it never replays; a budget cut stays missing")
    func covered() throws {
        let roomy = transfer(window: 200_000)
        #expect(roomy.receipt.included.map(\.position) == [4, 7])
        #expect(TaskHistoryDelta.covered(by: roomy.receipt, items: missed) == [4...8])
        let block = try #require(ContextTransferSelector.block(for: roomy))
        #expect(block.text?.contains("now fix the iOS build") == true)

        // Room for the message, not the long reply: the reply stays missing.
        let tight = transfer(window: 17_600)
        #expect(tight.receipt.included.map(\.position) == [4])
        #expect(TaskHistoryDelta.covered(by: tight.receipt, items: missed) == [4...6, 8...8])
    }
}
