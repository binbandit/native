import ACP
import SwiftUI

/// An AskUserQuestion call in the transcript: one quiet header, then one line per question with
/// its answer.
struct AskedQuestionsView: View {
    let questions: AskedQuestions
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "questionmark.bubble")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(questions.isWaiting ? .dsAttention : .dsTextTertiary)
                    .frame(width: DS.Size.rowLeading)
                Text(questions.isWaiting ? "Waiting for your answer" : title)
                    .foregroundStyle(questions.isWaiting ? .dsAttention : .dsTextSecondary)
                    .shimmering(questions.isWaiting)
            }
            .font(.dsCallout)
            ForEach(questions.entries, id: \.self) { entry in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text(entry.label)
                        .foregroundStyle(.dsTextTertiary)
                    answer(entry)
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .foregroundStyle(.dsTextTertiary)
                            .italic()
                    }
                }
                .font(.dsBody)
                .padding(.leading, DS.Size.rowLeading + DS.Space.sm)
                .textSelection(.enabled)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        questions.entries.count == 1 ? "Asked you a question" : "Asked you \(questions.entries.count) questions"
    }

    @ViewBuilder private func answer(_ entry: AskedQuestions.Entry) -> some View {
        switch entry.answer {
        case .chosen(let choice):
            Text(choice)
                .foregroundStyle(.dsTextPrimary)
        case .skipped:
            Text("Skipped")
                .foregroundStyle(.dsTextTertiary)
        case .waiting:
            Text("Answer in the card above the composer")
                .foregroundStyle(.dsTextTertiary)
        case .unanswered:
            Text("Not answered")
                .foregroundStyle(.dsTextTertiary)
        }
    }
}

#if DEBUG
#Preview("Asked questions") {
    VStack(alignment: .leading, spacing: DS.Space.lg) {
        ForEach(Array(TranscriptFixtures.askedQuestions.enumerated()), id: \.offset) { _, call in
            ToolCallView(call: call) { _ in }
        }
    }
    .padding(DS.Space.xl)
    .frame(width: DS.Size.contentColumn, alignment: .leading)
}
#endif
