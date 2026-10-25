import Foundation

/// Calendar boundaries keep yesterday's resting tasks out of today's working list.
public enum TaskDayFolding {
    public enum Interval: String, CaseIterable, Sendable {
        case day, week, never

        public var title: String {
            switch self {
            case .day: "A Day"
            case .week: "A Week"
            case .never: "Never"
            }
        }
    }

    public static func isEarlier(
        lastActivity: Date?, isAtRest: Bool, isUnread: Bool, isProtected: Bool,
        interval: Interval, now: Date, calendar: Calendar = .current
    ) -> Bool {
        guard interval != .never, isAtRest, !isUnread, !isProtected, let lastActivity else { return false }
        let today = calendar.startOfDay(for: now)
        let cutoff = interval == .week ? calendar.date(byAdding: .day, value: -6, to: today) ?? today : today
        return lastActivity < cutoff
    }

    /// Coordinator rows arrive with their children directly after them. Keep each family together
    /// and retain the user's relative ordering on both sides of the disclosure.
    public static func partition<Task>(
        _ tasks: [Task], isEarlier: (Task) -> Bool, isChild: (Task) -> Bool
    ) -> (current: [Task], earlier: [Task]) {
        var families: [[Task]] = []
        for task in tasks {
            if isChild(task), !families.isEmpty {
                families[families.count - 1].append(task)
            } else {
                families.append([task])
            }
        }
        var current: [Task] = []
        var earlier: [Task] = []
        for family in families {
            if family.allSatisfy(isEarlier) { earlier += family } else { current += family }
        }
        return (current, earlier)
    }
}
