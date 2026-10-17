import ACP
import SwiftUI

/// The session's pending question as a composer section: the docked form, or for a question with
/// no fields, a row to continue past it. Answers go through the session, as from any client.
struct AgentQuestionDock: View {
    let session: SessionModel
    let question: SessionModel.PendingQuestion

    var body: some View {
        let request = question.request
        if let schema = request.requestedSchema, let questionnaire = AgentQuestionnaire(message: request.message, schema: schema) {
            AgentQuestionSection(
                questionnaire: questionnaire,
                // It takes focus when nothing's being typed.
                takesFocus: session.draft.isEmpty,
                onSubmit: { content in Task { await session.answerQuestion(content) } },
                onSkipAll: { Task { await session.declineQuestion() } }
            )
        } else {
            AgentConfirmationRow(
                message: request.message,
                onContinue: { Task { await session.answerQuestion([:]) } },
                onSkip: { Task { await session.declineQuestion() } }
            )
        }
    }
}
