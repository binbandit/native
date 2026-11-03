/// Claude Code's AskUserQuestion call, read as its questions and how each was answered: the
/// transcript keeps "Color: Red", not the tool's raw text. The questions themselves are answered in
/// the composer's question card.
public struct AskedQuestions: Sendable {
    public struct Entry: Hashable, Sendable {
        /// The question's short header, or the question when it has none.
        public let label: String
        public let answer: Answer
        /// The user's note to the agent, if they added one.
        public let note: String?
    }

    public enum Answer: Hashable, Sendable {
        case chosen(String)
        case skipped
        /// Still waiting on the user.
        case waiting
        /// The turn ended before an answer.
        case unanswered
    }

    public let entries: [Entry]

    public init?(_ call: ToolCallState) {
        guard call.name == "AskUserQuestion" else { return nil }
        // Live answers arrive in the PostToolUse hook. session/load does not replay that hook:
        // the adapter carries the answers and annotations in the tool's input instead. An absent
        // answers map is still waiting; a present but empty map means the user skipped.
        let response =
            call.meta?["claudeCode"]?["toolResponse"]
            ?? (call.rawInput?["answers"] == nil ? nil : call.rawInput)
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

    public var isWaiting: Bool {
        entries.contains { $0.answer == .waiting }
    }
}
