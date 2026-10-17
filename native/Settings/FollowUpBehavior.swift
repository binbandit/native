import Foundation

/// What sending a message does while the agent is still working on the last one. Return does the
/// preferred behavior and ⌘Return the other.
enum FollowUpBehavior: String, CaseIterable, Identifiable, Sendable {
    /// Hold the message and send it when the turn ends.
    case queue
    /// Add the message to the running turn, so the agent changes course between steps. Agents
    /// without steering queue it instead.
    case steer

    /// The `@AppStorage` key for the user's preference.
    static let storageKey = "followUpBehavior"
    static let defaultValue = FollowUpBehavior.queue

    var id: Self { self }

    var opposite: FollowUpBehavior {
        switch self {
        case .queue: .steer
        case .steer: .queue
        }
    }

    var title: String {
        switch self {
        case .queue: "Queue"
        case .steer: "Steer"
        }
    }

    var explanation: String {
        switch self {
        case .queue: "Hold the message and send it when the agent finishes its current turn."
        case .steer: "Add the message to the turn in progress, so the agent adjusts between steps."
        }
    }
}
