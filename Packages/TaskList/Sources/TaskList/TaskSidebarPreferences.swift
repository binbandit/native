import Foundation
import Observation

/// All in view's additions are deliberate choices, independent of the legacy sidebar.
@MainActor @Observable
public final class TaskSidebarPreferences {
    public enum Fact: String, CaseIterable, Sendable {
        case needs, machines, ages, changes, agents, branches

        public var title: String {
            switch self {
            case .needs: "What Each Task Needs"
            case .machines: "Machines"
            case .ages: "Ages"
            case .changes: "Changes"
            case .agents: "Agents"
            case .branches: "Branches"
            }
        }
    }

    public private(set) var facts: Set<Fact>
    public private(set) var foldAfter: TaskDayFolding.Interval
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        facts = Set(
            Fact.allCases.filter { fact in
                (defaults.object(forKey: "sidebar.next.\(fact.rawValue)") as? Bool)
                    ?? (fact == .needs || fact == .machines)
            })
        foldAfter = defaults.string(forKey: "sidebar.next.foldAfter").flatMap(TaskDayFolding.Interval.init) ?? .day
    }

    public func shows(_ fact: Fact) -> Bool { facts.contains(fact) }

    public func set(_ fact: Fact, shown: Bool) {
        if shown { facts.insert(fact) } else { facts.remove(fact) }
        defaults.set(shown, forKey: "sidebar.next.\(fact.rawValue)")
    }

    public func setFoldAfter(_ interval: TaskDayFolding.Interval) {
        foldAfter = interval
        defaults.set(interval.rawValue, forKey: "sidebar.next.foldAfter")
    }
}
