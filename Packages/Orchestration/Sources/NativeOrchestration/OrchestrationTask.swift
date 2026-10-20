import Foundation

/// A task one session handed another agent, remembered for good so the session that started it,
/// and its siblings, can still reach it after Native or its host restarts. Sessions are named by
/// `TaskSessionRef`, the identity that outlives both.
public struct OrchestrationTask: Codable, Hashable, Sendable, Identifiable {
    /// What agents call it, such as `task-ab12cd`.
    public let id: String
    /// Changes only when the agent never saved the task's first session and it carried on in a fresh one.
    public var session: TaskSessionRef
    public let agentName: String
    /// What its card in the parent's transcript says.
    public let title: String
    public var parent: TaskSessionRef
    public let parentAgentName: String
    /// The folder it works in: its parent's. Nil in records from before it was kept.
    public var cwd: String?
    /// Nil in records from before it was kept.
    public var createdAt: Date?

    public init(
        id: String, session: TaskSessionRef, agentName: String, title: String, parent: TaskSessionRef,
        parentAgentName: String, cwd: String? = nil, createdAt: Date? = nil
    ) {
        self.id = id
        self.session = session
        self.agentName = agentName
        self.title = title
        self.parent = parent
        self.parentAgentName = parentAgentName
        self.cwd = cwd
        self.createdAt = createdAt
    }

    public var label: String {
        "\(id) (\(agentName): \(title))"
    }

    /// "Fix the bug · Codex" from a `label`, for naming a task whose record is gone without showing
    /// its id; nil when `label` isn't one.
    public static func displayName(fromLabel label: String) -> String? {
        guard let open = label.range(of: " ("), label.hasSuffix(")") else { return nil }
        let inner = label[open.upperBound..<label.index(before: label.endIndex)]
        guard let colon = inner.range(of: ": ") else { return nil }
        let agent = inner[..<colon.lowerBound]
        let title = inner[colon.upperBound...]
        guard !agent.isEmpty, !title.isEmpty else { return nil }
        return "\(title) · \(agent)"
    }

    /// Short enough for a model to copy reliably, and not among `taken`.
    public static func newID(avoiding taken: Set<String>) -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        while true {
            let id = "task-" + String((0..<6).map { _ in alphabet[Int.random(in: alphabet.indices)] })
            if !taken.contains(id) {
                return id
            }
        }
    }
}
