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
}
