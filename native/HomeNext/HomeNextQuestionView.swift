import ACP
import SwiftUI

/// Home hosts the composer's question unchanged, including digit keys and free text: the annotated
/// question with Fine print, the docked card without it.
struct HomeNextQuestionView: View {
    let session: SessionModel
    let question: SessionModel.PendingQuestion
    var isAvailable = true
    var focusRequested = false
    var didFocus: () -> Void = {}
    var openTask: (() -> Void)?
    let answer: (CreateElicitationResponse) -> Void

    @Experiment(.composerNext) private var composerNext

    var body: some View {
        if composerNext {
            AnnotatedQuestionView(
                agentName: session.agentName, questionnaire: question.questionnaire,
                message: question.request.message, isAvailable: isAvailable,
                focusRequested: focusRequested, didFocus: didFocus, openTask: openTask, inset: 0,
                onSubmit: { answer(.accept(content: $0)) }, onDecline: { answer(.decline) }
            )
            .padding(.top, -DS.Approval.askTop)
        } else if let questionnaire = question.questionnaire {
            AgentQuestionSection(
                questionnaire: questionnaire, takesFocus: true,
                onSubmit: { answer(.accept(content: $0)) }, onSkipAll: { answer(.decline) }
            )
            .padding(-DS.Space.md)
        } else {
            AgentConfirmationRow(
                message: question.request.message,
                onContinue: { answer(.accept(content: [:])) }, onSkip: { answer(.decline) })
        }
    }
}

#if DEBUG
#Preview("Next question - Choices") { HomeNextPreviewFixtures.page(.question) }
#Preview("Next question - Free text") { HomeNextPreviewFixtures.page(.questionText) }
#Preview("Next question - Several questions") { HomeNextPreviewFixtures.page(.questions) }
#Preview("Next question - Answer delivery fails") { HomeNextPreviewFixtures.page(.questionFailure) }
#Preview("Next question - Narrow") { HomeNextPreviewFixtures.page(.question, narrow: true) }
#Preview("Next question, Fine print - Choices") { HomeNextPreviewFixtures.page(.question, finePrint: true) }
#Preview("Next question, Fine print - Free text") { HomeNextPreviewFixtures.page(.questionText, finePrint: true) }
#Preview("Next question, Fine print - Several questions") {
    HomeNextPreviewFixtures.page(.questions, finePrint: true)
}
#Preview("Next question, Fine print - Answer delivery fails") {
    HomeNextPreviewFixtures.page(.questionFailure, finePrint: true)
}
#Preview("Next question, Fine print - Narrow") {
    HomeNextPreviewFixtures.page(.question, narrow: true, finePrint: true)
}
#endif
