import Foundation
import Testing
@testable import ACP

struct TranscriptTurnTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// The captured turn (read notes.txt, write out.txt, run ls), one second per update.
    private func capturedTurn(endingWith stopReason: StopReason = .endTurn) throws -> SessionState {
        var state = SessionState()
        state.appendUserMessage(Wire.promptText, at: at(0))
        var second: TimeInterval = 0
        for line in Wire.promptTurn {
            second += 1
            switch try Wire.event(line) {
            case .sessionUpdate(let notification):
                state.apply(notification.update, at: at(second))
            case .permissionRequest(let id, let request):
                state.requestPermission(request, id: id, at: at(second))
                state.resolvePermission(toolCallID: request.toolCall.toolCallId)
            case .elicitationRequest, .disconnected:
                break
            }
        }
        state.endTurn(stopReason, at: at(second + 1))
        return state
    }

    @Test func aLiveTurnIsTimedFromItsPromptToItsEnd() throws {
        let state = try capturedTurn()
        let turn = try #require(state.turns.only)
        #expect(turn.items == 0..<state.items.count)
        #expect(turn.startedAt == at(0))
        #expect(turn.stopReason == .endTurn)
        #expect(turn.duration == TimeInterval(Wire.promptTurn.count + 1))
        #expect(!turn.isOpen)
    }

    @Test func toolCallsKeepWhenTheyStartedAndFinished() throws {
        let state = try capturedTurn()
        let read = try #require(state.items.compactMap(\.toolCall).first { $0.id == Wire.readToolCallID })
        let started = try #require(read.startedAt)
        let finished = try #require(read.finishedAt)
        #expect(finished > started)
    }

    @Test func replayedHistoryHasNoTimes() throws {
        var state = SessionState()
        state.apply(.userMessageChunk(ContentChunk(content: .text("Hi"), messageId: nil)))
        state.apply(try Wire.update(Wire.readToolCall))
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("Hmm"), messageId: nil)))

        let turn = try #require(state.turns.only)
        #expect(turn.startedAt == nil)
        #expect(state.items.allSatisfy { $0.startedAt == nil })
        #expect(state.thinkingInterval(at: 2) == nil)
    }

    @Test func steeredMessagesJoinTheRunningTurn() throws {
        var state = SessionState()
        state.appendUserMessage("Run sleep 10", at: at(0))
        state.apply(try Wire.update(Wire.bashToolCall), at: at(1))
        state.appendUserMessage("Also tell me the date", steered: true, at: at(2))
        state.endTurn(.endTurn, at: at(12))
        state.appendUserMessage("Thanks", at: at(20))

        #expect(state.turns.map(\.items) == [0..<3, 3..<4])
        #expect(state.turns.map(\.duration) == [12, nil])
        #expect(state.turns.last?.isOpen == true)
    }

    @Test func itemsBeforeTheFirstPromptAreATurnOfTheirOwn() {
        var state = SessionState()
        state.apply(.agentMessageChunk(ContentChunk(content: .text("Starting"), messageId: nil)))
        state.appendUserMessage("Go", at: at(1))
        #expect(state.turns.map(\.items) == [0..<1, 1..<2])
    }

    @Test func thinkingEndsWhenTheAgentMovesOn() throws {
        var state = SessionState()
        state.appendUserMessage("Go", at: at(0))
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("Let me"), messageId: nil)), at: at(1))
        state.apply(.agentThoughtChunk(ContentChunk(content: .text(" think"), messageId: nil)), at: at(3))
        // Still the newest item of the running turn: still thinking.
        #expect(state.thinkingInterval(at: 1)?.start == at(1))
        #expect(state.thinkingInterval(at: 1)?.end == nil)

        state.apply(.agentMessageChunk(ContentChunk(content: .text("Done"), messageId: nil)), at: at(13))
        #expect(state.thinkingInterval(at: 1)?.end == at(13))
    }

    @Test func thinkingThatEndsTheTurnLastsUntilItsLastChunk() {
        var state = SessionState()
        state.appendUserMessage("Go", at: at(0))
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("Hmm"), messageId: nil)), at: at(1))
        state.apply(.agentThoughtChunk(ContentChunk(content: .text("…"), messageId: nil)), at: at(5))
        state.endTurn(.cancelled, at: at(9))
        #expect(state.thinkingInterval(at: 1)?.end == at(5))
    }

    @Test func cancellingStopsTheClocksOfOpenCalls() throws {
        var state = SessionState()
        state.appendUserMessage("Run it", at: at(0))
        state.apply(try Wire.update(Wire.bashToolCall), at: at(1))
        state.endTurn(.cancelled, at: at(4))
        let bash = try #require(state.items.compactMap(\.toolCall).first)
        #expect(bash.finishedAt == at(4))
        #expect(state.turns.first?.stopReason == .cancelled)
    }

    // MARK: - Summaries

    @Test func summaryCountsTheCapturedTurnsWork() throws {
        let state = try capturedTurn()
        let summary = state.summary(of: try #require(state.turns.only))
        #expect(summary.filesRead == 1)
        #expect(summary.commands == 1)
        #expect(summary.changedFiles == [.init(path: "/private/tmp/acp-research/sandbox/out.txt", added: 1, removed: 0)])
        #expect(summary.linesAdded == 1)
        #expect(summary.activityDescription == "Explored 1 file, edited 1 file, ran 1 command")
    }

    @Test func rejectedEditsChangeNothing() throws {
        var state = SessionState()
        state.appendUserMessage("Write it", at: at(0))
        for line in [Wire.writeToolCall, Wire.writeDiffUpdate] {
            state.apply(try Wire.update(line), at: at(1))
        }
        state.endTurn(.cancelled, at: at(2))
        let summary = state.summary(of: try #require(state.turns.only))
        #expect(summary.changedFiles.isEmpty)
        #expect(summary.activityDescription == nil)
    }

    @Test func editsToOneFileAddUp() {
        let diffs = [
            FileDiff(path: "/a.swift", oldText: "one\ntwo\n", newText: "one\n2\nthree\n"),
            FileDiff(path: "/a.swift", oldText: "x", newText: "y"),
            FileDiff(path: "/b.swift", oldText: nil, newText: "new\n"),
        ]
        let items = diffs.enumerated().map { index, diff in
            var call = ToolCallState(id: "edit-\(index)")
            call.kind = .edit
            call.status = .completed
            call.content = [.diff(diff)]
            return TranscriptItem.toolCall(call)
        }
        let summary = TurnSummary(items: items)
        #expect(summary.changedFiles == [
            .init(path: "/a.swift", added: 3, removed: 2),
            .init(path: "/b.swift", added: 1, removed: 0),
        ])
        #expect(summary.activityDescription == "Edited 2 files")
    }

    @Test func lineCountsIgnoreATrailingNewline() {
        #expect(FileDiff(path: "f", oldText: "a\nb\n", newText: "a\nb\nc\n").lineCounts == (1, 0))
        #expect(FileDiff(path: "f", oldText: nil, newText: "").lineCounts == (0, 0))
    }
}

private extension Array {
    /// The single element, or nil when there are none or several.
    var only: Element? {
        count == 1 ? first : nil
    }
}

private extension TranscriptItem {
    var toolCall: ToolCallState? {
        if case .toolCall(let call) = self { call } else { nil }
    }
}
