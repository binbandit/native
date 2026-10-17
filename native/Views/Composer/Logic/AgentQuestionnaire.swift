import ACP
import Foundation

/// An agent's structured questions, read from an ACP form elicitation (`elicitation/create`), the way
/// Claude Code sends its AskUserQuestion tool: a `question_<n>` select field per question, each with a
/// `question_<n>_custom` free-text companion. Other agents' form fields read as questions too: an
/// enum or `oneOf` is a select, an array of those a multi-select, anything else free text.
struct AgentQuestionnaire: Equatable {
    struct Option: Equatable, Identifiable {
        let value: String
        let title: String
        let description: String?

        var id: String { value }
    }

    struct Question: Equatable, Identifiable {
        let key: String
        /// A short label for the question (AskUserQuestion's `header`), when the agent gives one.
        let header: String?
        let prompt: String
        let options: [Option]
        let allowsMultiple: Bool
        /// The field that takes a typed answer, or a note on the picked option.
        let customKey: String?
        /// What the agent expects back; MCP servers' forms (through Codex) ask for more than text.
        let valueType: ValueType

        var id: String { key }
    }

    enum ValueType: Equatable {
        case string, boolean, number, integer

        init(schemaType: String?) {
            self = switch schemaType {
            case "boolean": .boolean
            case "number": .number
            case "integer": .integer
            default: .string
            }
        }
    }

    let questions: [Question]

    /// Nil when the schema has no field to ask about.
    init?(message: String, schema: JSONValue) {
        guard case .object(let properties)? = schema["properties"] else { return nil }
        // JSON objects are unordered here, so fields go in their natural order: question_2 before
        // question_10.
        let keys = properties.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let customKeys = Set(keys.filter { keys.contains(Self.questionKey(forCustom: $0)) })
        let fields = keys.filter { !customKeys.contains($0) }
        let questions = fields.compactMap { key -> Question? in
            guard let field = properties[key] else { return nil }
            let customKey = "\(key)_custom"
            return Question(
                key: key,
                header: field["title"]?.stringValue,
                // One question rides in the message; each of several carries its own text.
                prompt: field["description"]?.stringValue ?? (fields.count == 1 ? message : field["title"]?.stringValue ?? message),
                options: Self.options(in: field),
                allowsMultiple: field["type"]?.stringValue == "array",
                customKey: customKeys.contains(customKey) ? customKey : nil,
                valueType: ValueType(schemaType: field["type"]?.stringValue)
            )
        }
        guard !questions.isEmpty else { return nil }
        self.questions = questions
    }

    private static func questionKey(forCustom key: String) -> String {
        key.hasSuffix("_custom") ? String(key.dropLast("_custom".count)) : ""
    }

    /// A select's choices: `oneOf`/`anyOf` titled options or a plain `enum`, on the field or, for a
    /// multi-select, on its items.
    private static func options(in field: JSONValue) -> [Option] {
        let source = field["type"]?.stringValue == "array" ? field["items"] ?? .null : field
        for key in ["oneOf", "anyOf"] {
            if case .array(let entries)? = source[key] {
                return entries.compactMap { entry in
                    guard let value = entry["const"]?.stringValue else { return nil }
                    return Option(value: value, title: entry["title"]?.stringValue ?? value, description: entry["description"]?.stringValue)
                }
            }
        }
        if case .array(let values)? = source["enum"] {
            return values.compactMap(\.stringValue).map { Option(value: $0, title: $0, description: nil) }
        }
        if field["type"]?.stringValue == "boolean" {
            return [Option(value: "true", title: "Yes", description: nil), Option(value: "false", title: "No", description: nil)]
        }
        return []
    }
}
