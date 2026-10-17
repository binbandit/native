import Foundation

/// `/goal` typed in the composer. Native handles it for every agent rather than passing it through,
/// so goals behave the same everywhere; an agent with its own goal command gets it from the goal's
/// strategy instead.
public nonisolated enum GoalCommand: Codable, Hashable, Sendable {
    /// `/goal <objective>`
    case set(objective: String)
    /// `/goal` alone: open the goal editor.
    case edit
    case pause
    case resume
    /// `/goal clear` (also `stop`, `cancel`, `off`).
    case clear

    /// The command typed in `draft`, or nil when it isn't one.
    init?(parsing draft: String) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("/goal") else { return nil }
        let rest = text.dropFirst(5)
        // "/goals" or "/goalkeeper" are someone else's commands.
        if let next = rest.first, !next.isWhitespace {
            return nil
        }
        let argument = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        switch argument.lowercased() {
        case "": self = .edit
        case "pause": self = .pause
        case "resume", "continue": self = .resume
        case "clear", "stop", "cancel", "off": self = .clear
        default: self = .set(objective: argument)
        }
    }

    /// How the composer's command list describes it.
    public static let summary = "Keep the agent working until an objective is met"
    public static let usage = "/goal <objective> · /goal pause · /goal resume · /goal clear"
}
