import Foundation

/// The prompts Native sends to drive a goal, and how to recognize them again. Each opens with a tag
/// line, so a transcript (live, or replayed from the agent's history) can show them as compact goal
/// rows instead of walls of instructions.
public nonisolated enum GoalPrompt: Hashable, Sendable {
    /// Sets the goal and explains the status-line protocol.
    case kickoff(objective: String)
    /// Asks the agent to keep going; `iteration` is the one about to start, counting from 1.
    case continuation(objective: String, iteration: Int)

    public init?(parsing text: String) {
        let lines = text.components(separatedBy: .newlines)
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else { return nil }
        if first == "<goal>", let end = lines.firstIndex(of: "</goal>") {
            self = .kickoff(objective: Self.objective(in: lines[1..<end]))
        } else if first.hasPrefix(Self.continuationOpening), first.hasSuffix("\">"),
            let iteration = Int(first.dropFirst(Self.continuationOpening.count).dropLast(2)),
            let end = lines.firstIndex(of: "</goal-continue>")
        {
            self = .continuation(objective: Self.objective(in: lines[1..<end]), iteration: iteration)
        } else {
            return nil
        }
    }

    public var objective: String {
        switch self {
        case .kickoff(let objective), .continuation(let objective, _): objective
        }
    }

    private static let continuationOpening = "<goal-continue iteration=\""

    private static func objective(in lines: ArraySlice<String>) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Writing

    public static let protocolLines = """
        GOAL: continuing - <what you'll do next>
        GOAL: blocked - <what you need from the user>
        GOAL: complete - <how you verified it>
        """

    public static func kickoffText(objective: String, usage: GoalUsage) -> String {
        var text = """
            <goal>
            \(objective)
            </goal>

            This is a goal: keep working on it across turns. After each of your turns Native asks you to \
            continue, until you report that the goal is complete or that you're blocked.

            End every reply with one status line, on a line of its own:
            \(protocolLines)

            Report complete only after checking that the goal is met, for example by running the tests or \
            reading back the result. Report blocked only when you can't go on without the user, such as \
            for a decision only they can make, credentials, or access; otherwise make reasonable choices \
            yourself and keep going.

            Don't end a turn just to wait: if a command or build is still running, wait for it within the \
            same turn. Every reply starts another iteration.
            """
        if let remaining = usage.remainingText {
            text += "\n\nBudget: \(remaining.replacingOccurrences(of: " left", with: ""))."
        }
        return text
    }

    /// `reminder` follows a reply that had no status line, so the agent knows Native couldn't read it.
    public static func continuationText(objective: String, usage: GoalUsage, reminder: Bool, resumed: Bool) -> String {
        var notes: [String] = [
            resumed ? "Pick the goal back up where you left off." : "Keep working toward the goal.",
            "If something is still running, wait for it within this turn.",
        ]
        if let remaining = usage.remainingText {
            notes.append("Budget: \(remaining).")
        }
        if usage.isLastIteration {
            notes.append(
                "This is the last iteration the budget allows, so wrap up: leave the work in a good state and report where it stands."
            )
        }
        if reminder {
            notes.append(
                "Your last reply didn't end with a status line, so Native couldn't tell where the goal stands.")
        }
        return """
            \(continuationOpening)\(usage.iterations + 1)">
            \(objective)
            </goal-continue>

            \(notes.joined(separator: " "))

            End your reply with one status line:
            \(protocolLines)
            """
    }
}
