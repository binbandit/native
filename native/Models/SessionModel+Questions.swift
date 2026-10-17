import ACP
import Foundation

// Questions from the agent: structured input it asks for mid-turn (`elicitation/create`), such as
// Claude Code's AskUserQuestion. Every client answers through these methods.
extension SessionModel {
    struct PendingQuestion: Identifiable {
        let id: RequestID
        let request: CreateElicitationRequest
    }

    /// The question to answer now; later ones wait behind it.
    var pendingQuestion: PendingQuestion? {
        questions.first
    }

    /// Holds a question for the user. Only forms can be answered here; anything else is cancelled
    /// so the agent isn't left waiting.
    func requestQuestion(_ request: CreateElicitationRequest, id: RequestID) {
        guard request.mode == .form, request.requestedSchema != nil else {
            Task { try? await connection.respond(to: id, with: CreateElicitationResponse.cancel) }
            return
        }
        questions.append(PendingQuestion(id: id, request: request))
    }

    /// Answers the current question with the filled-in fields.
    func answerQuestion(_ content: [String: JSONValue]) async {
        await respondToQuestion(.accept(content: content))
    }

    /// Answers the current question with "skipped": the agent carries on without the answers.
    func declineQuestion() async {
        await respondToQuestion(.decline)
    }

    /// Withdraws every open question, as cancelling the turn requires.
    func cancelQuestions() async {
        let open = questions
        questions.removeAll()
        for question in open {
            try? await connection.respond(to: question.id, with: CreateElicitationResponse.cancel)
        }
    }

    private func respondToQuestion(_ response: CreateElicitationResponse) async {
        guard !questions.isEmpty else { return }
        let question = questions.removeFirst()
        do {
            try await connection.respond(to: question.id, with: response)
        } catch {
            state.appendNotice("Couldn’t send your answer: \(error.localizedDescription)", isError: true)
        }
    }
}
