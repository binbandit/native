import Foundation

/// Why a run started, as its history shows it.
nonisolated enum AutomationRunReason: Codable, Hashable, Sendable {
    case scheduled(Date)
    /// Its time passed while Native wasn't running; it ran once on the next launch.
    case missed(Date)
    case event(AutomationOccurrence)
    case manual

    var label: String {
        switch self {
        case .scheduled(let date): "Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))"
        case .missed(let date): "Missed \(date.formatted(date: .abbreviated, time: .shortened)) while Native was closed"
        case .event(let occurrence): occurrence.context
        case .manual: "Run by you"
        }
    }

    var context: String? {
        if case .event(let occurrence) = self { occurrence.context } else { nil }
    }
}
