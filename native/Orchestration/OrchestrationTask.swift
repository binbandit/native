import Foundation

/// A task one session handed another agent, remembered across launches so the session that
/// started it, and its siblings, can still reach it after Native restarts. Sessions are named by
/// their `SessionKey`, the identity that outlives a launch.
struct OrchestrationTask: Codable, Sendable {
    /// What agents call it, such as `task-ab12cd`.
    let id: String
    let session: SessionKey
    let agentName: String
    /// What its card in the parent's transcript says.
    let title: String
    let parent: SessionKey
    let parentAgentName: String

    var label: String {
        "\(id) (\(agentName): \(title))"
    }

    /// "Fix the bug · Codex" from a `label`, for naming a task whose record is gone without showing
    /// its id; nil when `label` isn't one.
    static func displayName(fromLabel label: String) -> String? {
        guard let open = label.range(of: " ("), label.hasSuffix(")") else { return nil }
        let inner = label[open.upperBound..<label.index(before: label.endIndex)]
        guard let colon = inner.range(of: ": ") else { return nil }
        let agent = inner[..<colon.lowerBound]
        let title = inner[colon.upperBound...]
        guard !agent.isEmpty, !title.isEmpty else { return nil }
        return "\(title) · \(agent)"
    }
}
