import Foundation

/// A bounded, local handoff draft. It quotes visible messages instead of inventing conclusions;
/// the user reviews it before another agent receives any of the task's context.
public enum TaskHandoff {
    public static func draft(
        title: String, state: SessionState, objective: String? = nil,
        changedPaths: [String] = [], fileStatus: String? = nil, openQuestion: String? = nil
    ) -> String {
        let messages = state.items.compactMap { item -> TranscriptMessage? in
            guard case .message(let message) = item, message.role != .thought else { return nil }
            return message
        }
        let firstPrompt = messages.first(where: { $0.role == .user })?.text
        let inheritedGoal = firstPrompt.flatMap { text -> String? in
            guard text.hasPrefix("Continue this task in the current working tree."),
                let start = text.range(of: "\nGoal\n"),
                let end = text.range(of: "\n\nRecent progress\n", range: start.upperBound..<text.endIndex)
            else { return nil }
            return String(text[start.upperBound..<end.lowerBound])
        }
        let goal = nonempty(objective) ?? nonempty(inheritedGoal) ?? firstPrompt ?? title
        let recent = messages.suffix(4).map {
            "\($0.role == .user ? "User" : "Agent"): \(excerpt($0.text, limit: 1_200))"
        }.joined(separator: "\n\n")
        let recordedPaths = state.turns.flatMap { state.summary(of: $0).changedFiles.map(\.path) }
        let paths = Array(Set(changedPaths + recordedPaths)).sorted()
        var files = paths.prefix(80).map { "- \(excerpt($0, limit: 300))" }.joined(separator: "\n")
        if files.isEmpty { files = "No changed files recorded. Inspect the working tree before continuing." }
        if paths.count > 80 { files += "\n(\(paths.count - 80) more paths omitted.)" }
        if let fileStatus { files += "\n\(fileStatus)" }
        let plan = state.plan.prefix(12).map { "- [\($0.status.rawValue)] \(excerpt($0.content, limit: 240))" }
            .joined(separator: "\n")
        let question =
            nonempty(openQuestion)
            ?? messages.last(where: { $0.role == .agent })?.text.split(separator: "\n")
            .last(where: { $0.contains("?") }).map(String.init)
            ?? "No explicit open question recorded. Confirm the next step from the context above."
        return """
            Continue this task in the current working tree. Keep its branch and existing changes.
            Native prepared these excerpts locally; they may be incomplete. Verify the current files before acting.

            Task: \(excerpt(title, limit: 240))

            Goal
            \(excerpt(goal, limit: 1_200))

            Recent progress
            \(recent.isEmpty ? "No conversation recorded yet." : recent)
            \(plan.isEmpty ? "" : "\nLatest plan\n" + plan)

            Files changed so far (reported edits, branch and working tree)
            \(files)

            Open question or next step
            \(excerpt(question, limit: 1_200))
            """
    }

    private static func nonempty(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    private static func excerpt(_ value: String, limit: Int) -> String {
        let prefix = String(value.prefix(limit))
        return prefix.count < value.count ? prefix + "\n[Excerpt truncated]" : prefix
    }
}
