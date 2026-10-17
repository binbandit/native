import ACP
import Foundation

/// Who put a context category there: the agent itself, the user's setup, or the conversation.
/// Three groups rather than one color per category keeps the breakdown's chart legible for
/// colorblind readers; each category is still its own segment and table row.
enum ContextGroup: CaseIterable, Hashable {
    /// System prompt and built-in tools.
    case builtIn
    /// MCP servers, memory files, skills and custom agents the user set up.
    case configured
    /// Messages, tool calls and their results.
    case conversation

    init(category name: String) {
        let name = name.lowercased()
        if name.hasPrefix("message") || name.contains("conversation") {
            self = .conversation
        } else if ["mcp", "memory", "skill", "agent", "plugin"].contains(where: name.contains) {
            self = .configured
        } else {
            self = .builtIn
        }
    }

    var title: String {
        switch self {
        case .builtIn: "Built-in"
        case .configured: "Your setup"
        case .conversation: "Conversation"
        }
    }
}
