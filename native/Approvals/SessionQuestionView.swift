import ACP
import SwiftUI

/// The task's oldest question in the composer's place (Fine print), answered through the session
/// as from any client.
struct SessionQuestionView: View {
    let session: SessionModel
    let question: SessionModel.PendingQuestion

    var body: some View {
        AnnotatedQuestionView(
            agentName: session.agentName,
            questionnaire: question.questionnaire,
            message: question.request.message,
            // It takes the keys when nothing's being typed.
            takesFocus: session.draft.isEmpty,
            isAvailable: session.phase != .disconnected,
            focusRequested: session.wantsComposerFocus,
            didFocus: { session.wantsComposerFocus = false },
            onSubmit: { await session.answerQuestion($0) },
            onDecline: { await session.declineQuestion() }
        )
        .id(question.id)
    }
}

#if DEBUG
#Preview("Session question") {
    DSPreviewPair { AskPreviewFixtures.questionComposer().frame(width: 850) }
}
#endif
