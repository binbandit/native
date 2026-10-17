import Foundation

/// One way an automation starts. Every automation can also be run by hand.
public nonisolated enum AutomationTrigger: Codable, Hashable, Sendable {
    case schedule(AutomationSchedule)
    case event(AutomationEventKind)

    public var summary: String {
        switch self {
        case .schedule(let schedule): schedule.summary()
        case .event(let kind): "When " + kind.clause
        }
    }

    public var systemImage: String {
        switch self {
        case .schedule: "clock"
        case .event(let kind): kind.systemImage
        }
    }
}
