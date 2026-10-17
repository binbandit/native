import Foundation

/// One way an automation starts. Every automation can also be run by hand.
nonisolated enum AutomationTrigger: Codable, Hashable, Sendable {
    case schedule(AutomationSchedule)
    case event(AutomationEventKind)

    var summary: String {
        switch self {
        case .schedule(let schedule): schedule.summary()
        case .event(let kind): "When " + kind.label.prefix(1).lowercased() + kind.label.dropFirst()
        }
    }

    var systemImage: String {
        switch self {
        case .schedule: "clock"
        case .event(let kind): kind.systemImage
        }
    }
}
