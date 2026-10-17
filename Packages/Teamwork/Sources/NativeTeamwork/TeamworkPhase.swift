import Foundation

/// Where an expedition stands, computed from its parts, never stored.
public nonisolated enum TeamworkPhase: String, Codable, Hashable, Sendable {
    /// Making the base, or the lead drafting or revising the route.
    case planning
    /// A route waits for the user.
    case reviewing
    case underway
    /// Held by the user: turns in flight finish, nothing new goes out.
    case paused
    /// Something waits on the user.
    case needsYou
    /// A provider limit stopped the crew; work resumes at the reset.
    case limited
    /// Every leg is done; the lead is writing the debrief, or the pull request is opening.
    case debriefing
    case complete
    case stopped

    public var label: String {
        switch self {
        case .planning: "Planning"
        case .reviewing: "Route ready"
        case .underway: "Underway"
        case .paused: "Paused"
        case .needsYou: "Needs you"
        case .limited: "Limited"
        case .debriefing: "Debriefing"
        case .complete: "Complete"
        case .stopped: "Stopped"
        }
    }

    public var needsUser: Bool {
        self == .reviewing || self == .needsYou
    }

    public var isOver: Bool {
        self == .complete || self == .stopped
    }
}
