import Foundation
import Testing

@testable import ACP

struct AskedQuestionsTests {
    @Test func answeredQuestionSurvivesSessionLoadReplay() throws {
        var state = SessionState()
        state.appendUserMessage("Ask me which color I prefer.")
        var question = try Self.question()
        state.apply(.toolCall(question))
        #expect(try #require(Self.questions(in: state)).isWaiting)
        question.meta = .object([
            "claudeCode": .object([
                "toolResponse": .object([
                    "questions": try #require(question.rawInput?["questions"]),
                    "answers": .object(["Which color do you prefer?": .string("Red")]),
                ])
            ])
        ])
        state.apply(.toolCallUpdate(question))
        state.apply(try Wire.update(Self.replay[2]))
        state.apply(try Wire.update(Self.replay[3]))
        state.endTurn(.endTurn)
        let liveAnswers = try #require(Self.questions(in: state)).entries.map(\.answer)
        #expect(liveAnswers == [.chosen("Red")])

        // Reopening starts with a fresh reducer, not the live hook metadata.
        state = SessionState()
        for line in Self.replay {
            state.apply(try Wire.update(line))
        }
        let call = try #require(
            state.items.compactMap { item -> ToolCallState? in
                if case .toolCall(let call) = item { call } else { nil }
            }.first)
        #expect(call.status == .completed)
        #expect(call.meta?["claudeCode"]?["toolResponse"] == nil)
        #expect(call.rawInput?["answers"]?["Which color do you prefer?"] == .string("Red"))
        let questions = try #require(AskedQuestions(call))
        #expect(!questions.isWaiting)
        #expect(questions.entries.map(\.answer) == liveAnswers)
        #expect(state.items.count == 3)
        guard case .message(let reply) = state.items.last else {
            Issue.record("Expected the agent's reply after the answered question")
            return
        }
        #expect(reply.text == "You chose Red.")
    }

    @Test func replayRetainsSkippedAnswersAndNotes() throws {
        var update = try Self.question()
        update.rawInput = .object([
            "questions": try #require(update.rawInput?["questions"]),
            "answers": .object([:]),
        ])
        var state = SessionState()
        state.apply(.toolCall(update))
        #expect(try #require(Self.questions(in: state)).entries.map(\.answer) == [.skipped])

        update.rawInput = .object([
            "questions": try #require(update.rawInput?["questions"]),
            "answers": .object(["Which color do you prefer?": .string("Red")]),
            "annotations": .object(["Which color do you prefer?": .object(["notes": .string("Matches the logo")])]),
        ])
        state.apply(.toolCallUpdate(update))
        let questions = try #require(Self.questions(in: state))
        #expect(questions.entries.map(\.answer) == [.chosen("Red")])
        #expect(questions.entries.map(\.note) == ["Matches the logo"])
    }

    @Test func liveResponseTakesPrecedenceAndSurvivesCompletion() throws {
        var update = try Self.question()
        update.rawInput = .object([
            "questions": try #require(update.rawInput?["questions"]),
            "answers": .object(["Which color do you prefer?": .string("Blue")]),
        ])
        update.meta = .object([
            "claudeCode": .object([
                "toolResponse": .object([
                    "answers": .object(["Which color do you prefer?": .string("Red")])
                ])
            ])
        ])
        var state = SessionState()
        state.apply(.toolCall(update))
        state.apply(try Wire.update(Self.replay[2]))
        #expect(try #require(Self.questions(in: state)).entries.map(\.answer) == [.chosen("Red")])
    }

    @Test(arguments: [ToolCallStatus.pending, .inProgress, .failed, .cancelled, .interrupted, .unreported])
    func questionsWithoutAnswersKeepTheirExistingState(status: ToolCallStatus) throws {
        var update = try Self.question()
        update.status = status
        var state = SessionState()
        state.apply(.toolCall(update))
        let questions = try #require(Self.questions(in: state))
        #expect(questions.entries.map(\.answer) == [status.isFinished ? .unanswered : .waiting])
        #expect(questions.isWaiting == !status.isFinished)
    }

    private static func question() throws -> ToolCallUpdate {
        guard case .toolCall(var update) = try Wire.update(replay[1]),
            case .object(var input) = update.rawInput
        else {
            throw QuestionFixtureError.invalidCall
        }
        input.removeValue(forKey: "answers")
        update.rawInput = .object(input)
        return update
    }

    private static func questions(in state: SessionState) -> AskedQuestions? {
        state.items.compactMap { item -> AskedQuestions? in
            if case .toolCall(let call) = item { AskedQuestions(call) } else { nil }
        }.first
    }

    private enum QuestionFixtureError: Error {
        case invalidCall
    }

    // Captured from claude-agent-acp 0.93.0's session/load notification converter with fixture
    // messages based on the live AskUserQuestion capture in TranscriptFixtures. Replay sends the
    // answered input, but does not run the PostToolUse hook that supplies live toolResponse meta.
    private static let replay = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"question-replay","update":{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Ask me which color I prefer."}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"question-replay","update":{"_meta":{"claudeCode":{"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq","sessionUpdate":"tool_call","name":"AskUserQuestion","rawInput":{"questions":[{"question":"Which color do you prefer?","header":"Color","multiSelect":false,"options":[{"label":"Red","description":"A warm, bold color"},{"label":"Blue","description":"A cool, calm color"}]}],"answers":{"Which color do you prefer?":"Red"}},"status":"pending","title":"Which color do you prefer?","kind":"other","content":[{"type":"content","content":{"type":"text","text":"Which color do you prefer?"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"question-replay","update":{"_meta":{"claudeCode":{"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq","sessionUpdate":"tool_call_update","status":"completed","rawOutput":"User has answered your questions: \"Which color do you prefer?\"=\"Red\". You can now continue with the user's answers in mind.","content":[{"type":"content","content":{"type":"text","text":"User has answered your questions: \"Which color do you prefer?\"=\"Red\". You can now continue with the user's answers in mind."}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"question-replay","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"You chose Red."}}}}"#,
    ]
}
