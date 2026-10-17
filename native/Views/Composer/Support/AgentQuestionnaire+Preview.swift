#if DEBUG
import ACP
import Foundation

extension AgentQuestionnaire {
    /// Three questions as Claude Code's adapter (claude-agent-acp 0.93) sends AskUserQuestion: the
    /// field shapes of a captured `elicitation/create`, with the per-question text a multi-question
    /// form carries in each field's description.
    static let preview: AgentQuestionnaire? = {
        let schema = """
            {"type": "object", "properties": {
              "question_0": {"type": "string", "title": "Storage", "description": "Where should drafts be saved?",
                "oneOf": [{"const": "UserDefaults", "title": "UserDefaults", "description": "Simple and synchronous; fine for a few KB"},
                          {"const": "Application Support", "title": "Application Support", "description": "A JSON file per session; survives larger drafts"},
                          {"const": "SwiftData", "title": "SwiftData", "description": "Queryable, but a new dependency for one feature"}]},
              "question_0_custom": {"type": "string", "title": "Other", "description": "Type your own answer, or add a note to the option you chose above (optional)."},
              "question_1": {"type": "array", "title": "Platforms", "description": "Which platforms need it first?",
                "items": {"anyOf": [{"const": "macOS", "title": "macOS"}, {"const": "iPadOS", "title": "iPadOS"}]}},
              "question_1_custom": {"type": "string", "title": "Other", "description": "Type your own answer to add to your selection above (optional)."},
              "question_2": {"type": "string", "title": "Color", "description": "Which color do you prefer?",
                "oneOf": [{"const": "Red", "title": "Red", "description": "A warm, bold color"},
                          {"const": "Blue", "title": "Blue", "description": "A cool, calm color"}]},
              "question_2_custom": {"type": "string", "title": "Other", "description": "Type your own answer, or add a note to the option you chose above (optional)."}
            }}
            """
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(schema.utf8)) else { return nil }
        return AgentQuestionnaire(message: "Please answer the following questions.", schema: value)
    }()
}
#endif
