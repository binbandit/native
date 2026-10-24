import ACP
import Foundation

/// Explicit user assignments, independent of an agent's delegated task family.
public struct CoordinatorScope: Sendable {
    public let title: String
    public let tasks: [OrchestrationTask]

    public init(title: String, tasks: [OrchestrationTask]) {
        self.title = title
        self.tasks = tasks
    }

    /// Only a permission choice advertised as read-only qualifies. Plan modes may allow edits.
    public static func readOnlyChoice(in options: [ConfigOption]) -> (option: ConfigOption, value: String)? {
        for option in options where option.category == "mode" {
            guard case .select(_, let choices) = option.kind else { continue }
            if let choice = choices.first(where: {
                [$0.value, $0.name].contains { $0.lowercased().filter(\.isLetter) == "readonly" }
            }) {
                return (option, choice.value)
            }
        }
        return nil
    }

    /// A local excerpt, never reasoning or raw tool output, with a fixed upper bound.
    public static func summary(of state: SessionState) -> String {
        let messages = state.items.reversed().lazy.compactMap { item -> String? in
            switch item {
            case .message(let message) where message.role != .thought:
                return "\(message.role == .user ? "User" : "Agent"): " + String(message.text.prefix(1200))
            case .sessionMessage(let message):
                return "Task message: " + String(message.text.prefix(1200))
            default: return nil
            }
        }
        return messages.prefix(4).reversed().joined(separator: "\n\n")
    }
}
