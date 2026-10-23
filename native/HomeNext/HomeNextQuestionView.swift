import ACP
import SwiftUI

/// Home hosts the composer's form unchanged, including digit keys and free text.
struct HomeNextQuestionView: View {
    let question: SessionModel.PendingQuestion
    let answer: (CreateElicitationResponse) -> Void

    var body: some View {
        if let schema = question.request.requestedSchema,
            let questionnaire = AgentQuestionnaire(message: question.request.message, schema: schema)
        {
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
#endif
