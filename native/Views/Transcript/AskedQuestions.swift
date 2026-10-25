import ACP
import SwiftUI

/// Claude Code's AskUserQuestion call, read as its questions and how each was answered: the
/// transcript keeps "Color: Red", not the tool's raw text. The questions themselves are answered in
/// the composer's question card.
struct AskedQuestions {
    struct Entry: Hashable {
        /// The question's short header, or the question when it has none.
        let label: String
        let answer: Answer
        /// The user's note to the agent, if they added one.
        let note: String?
    }

    enum Answer: Hashable {
        case chosen(String)
        case skipped
        /// Still waiting on the user.
        case waiting
        /// The turn ended before an answer.
        case unanswered
    }

    let entries: [Entry]

    init?(_ call: ToolCallState) {
        guard call.name == "AskUserQuestion" else { return nil }
        let response = call.meta?["claudeCode"]?["toolResponse"]
        guard case .array(let questions)? = response?["questions"] ?? call.rawInput?["questions"] else {
            entries = []
            return
        }
        let answers = response?["answers"]
        entries = questions.compactMap { question in
            guard let text = question["question"]?.stringValue else { return nil }
            let header = question["header"]?.stringValue
            let answer: Answer =
                if response != nil {
                    // Answered: an empty map means the user skipped every question.
                    answers?[text]?.stringValue.map(Answer.chosen) ?? .skipped
                } else if [.failed, .cancelled, .interrupted, .unreported].contains(call.status) {
                    .unanswered
                } else {
                    .waiting
                }
            let note = response?["annotations"]?[text]?["notes"]?.stringValue
            return Entry(label: header.flatMap { $0.isEmpty ? nil : $0 } ?? text, answer: answer, note: note)
        }
    }

    var isWaiting: Bool {
        entries.contains { $0.answer == .waiting }
    }
}

/// An AskUserQuestion call in the transcript: one quiet header, then one line per question with
/// its answer.
struct AskedQuestionsView: View {
    let questions: AskedQuestions
    /// Fine print puts the question in the composer's place rather than in a card above it.
    @Experiment(.composerNext) private var composerNext

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
            Text(composerNext ? "Answer in the composer" : "Answer in the card above the composer")
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
