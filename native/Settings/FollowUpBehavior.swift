import Foundation

/// What sending a message does while the agent is still working on the last one. Return does the
/// preferred behavior and ⌘Return the other.
enum FollowUpBehavior: String, CaseIterable, Identifiable, Sendable {
    /// Hold the message and send it when the turn ends.
    case queue
    /// Add input without cancelling running tools, waiting for their completion when needed.
    case steer

    /// The `@AppStorage` key for the user's preference.
    static let storageKey = "followUpBehavior"
    /// Steer: a message typed while the agent works is usually a correction it should see now.
    static let defaultValue = FollowUpBehavior.steer

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
        case .steer: "Let running tools finish, then add the message so the agent adjusts between steps."
        }
    }
}
