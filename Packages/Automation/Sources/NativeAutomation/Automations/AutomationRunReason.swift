import Foundation

/// Why a run started, as its history shows it.
public nonisolated enum AutomationRunReason: Codable, Hashable, Sendable {
    case scheduled(Date)
    /// Its time passed while Native wasn't running; it ran once on the next launch.
    case missed(Date)
    case event(AutomationOccurrence)
    case manual

    public var label: String {
        switch self {
        case .scheduled(let date): "Scheduled for \(date.formatted(date: .abbreviated, time: .shortened))"
        case .missed(let date): "Missed \(date.formatted(date: .abbreviated, time: .shortened)) while Native was closed"
        case .event(let occurrence): occurrence.headline
        case .manual: "Run by you"
        }
    }

    public var context: String? {
        if case .event(let occurrence) = self { occurrence.context } else { nil }
    }
}
