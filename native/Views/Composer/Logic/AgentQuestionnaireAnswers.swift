import ACP
import Foundation

/// The user's answers so far, and the elicitation content they make.
struct AgentQuestionnaireAnswers: Equatable {
    private(set) var picks: [String: [String]] = [:]
    var typed: [String: String] = [:]

    func isPicked(_ option: AgentQuestionnaire.Option, in question: AgentQuestionnaire.Question) -> Bool {
        picks[question.key, default: []].contains(option.value)
    }

    func initialHighlight(in question: AgentQuestionnaire.Question) -> Int {
        question.options.firstIndex { isPicked($0, in: question) } ?? 0
    }

    mutating func answerHighlightedOption(_ index: Int, in question: AgentQuestionnaire.Question) {
        guard !question.allowsMultiple, typedAnswer(for: question).isEmpty, question.options.indices.contains(index)
        else { return }
        pick(question.options[index], in: question)
    }

    /// Picks an option; a multi-select toggles it, a single select replaces the pick.
    mutating func pick(_ option: AgentQuestionnaire.Option, in question: AgentQuestionnaire.Question) {
        var current = picks[question.key, default: []]
        if question.allowsMultiple {
            if let index = current.firstIndex(of: option.value) {
                current.remove(at: index)
            } else {
                current.append(option.value)
            }
        } else {
            current = [option.value]
        }
        picks[question.key] = current
    }

    /// Leaves a question unanswered.
    mutating func clear(_ question: AgentQuestionnaire.Question) {
        picks[question.key] = nil
        typed[Self.textKey(for: question)] = nil
    }

    func isAnswered(_ question: AgentQuestionnaire.Question) -> Bool {
        !picks[question.key, default: []].isEmpty || !typedAnswer(for: question).isEmpty
    }

    /// Where a question's typed text goes: its companion field, or the question itself when it has
    /// no options to pick.
    static func textKey(for question: AgentQuestionnaire.Question) -> String {
        question.customKey ?? question.key
    }

    func typedAnswer(for question: AgentQuestionnaire.Question) -> String {
        typed[Self.textKey(for: question), default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The `accept` content: picks under each question's key, typed text under its custom key.
    /// Skipped questions are left out, which the agent reads as unanswered.
    func content(for questionnaire: AgentQuestionnaire) -> [String: JSONValue] {
        var content: [String: JSONValue] = [:]
        for question in questionnaire.questions {
            let picked = picks[question.key, default: []]
            if question.allowsMultiple, !picked.isEmpty {
                content[question.key] = .array(picked.map(JSONValue.string))
            } else if let first = picked.first {
                content[question.key] = question.valueType == .boolean ? .bool(first == "true") : .string(first)
            } else if question.customKey == nil, !typedAnswer(for: question).isEmpty {
                // A free-text question has no companion field: the text is the answer.
                content[question.key] = Self.value(typedAnswer(for: question), as: question.valueType)
            }
            if let customKey = question.customKey, !typedAnswer(for: question).isEmpty {
                content[customKey] = .string(typedAnswer(for: question))
            }
        }
        return content
    }

    /// Typed text as the type the field asks for; text that isn't a number stays text, for the agent
    /// to reject with its own message.
    private static func value(_ text: String, as type: AgentQuestionnaire.ValueType) -> JSONValue {
        switch type {
        case .number: Double(text).map(JSONValue.number) ?? .string(text)
        case .integer: Int(text).map { .number(Double($0)) } ?? .string(text)
        case .boolean, .string: .string(text)
        }
    }
}
