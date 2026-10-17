import Foundation

/// Everything Automations keeps: the automations, their run history, when each was last checked
/// against its schedule, and the last GitHub poll to compare the next one with. Plain Codable
/// state, so it can live in the app today and in the durable host later.
public nonisolated struct AutomationBook: Codable, Hashable, Sendable {
    public var automations: [Automation] = []
    /// Newest first.
    public var runs: [AutomationRun] = []
    public var lastChecked: [Automation.ID: Date] = [:]
    public var pullRequests: [PullRequestSnapshot]?
    /// Events already acted on, so a repeated poll never starts a second run.
    public var handledEvents: Set<String> = []

    /// History kept per automation; older runs drop off.
    public static let historyLimit = 50
    public static let handledEventLimit = 2_000

    public func automation(_ id: Automation.ID) -> Automation? {
        automations.first { $0.id == id }
    }

    public func runs(of id: Automation.ID) -> [AutomationRun] {
        runs.filter { $0.automation == id }
    }

    public func openRun(of id: Automation.ID) -> AutomationRun? {
        runs.first { $0.automation == id && $0.status.isOpen }
    }

    public mutating func save(_ automation: Automation) {
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[index] = automation
        } else {
            automations.append(automation)
        }
    }

    public mutating func delete(_ id: Automation.ID) {
        automations.removeAll { $0.id == id }
        runs.removeAll { $0.automation == id }
        lastChecked[id] = nil
    }

    public mutating func record(_ run: AutomationRun) {
        runs.insert(run, at: 0)
        var kept = 0
        runs.removeAll { candidate in
            guard candidate.automation == run.automation else { return false }
            kept += 1
            return kept > Self.historyLimit
        }
    }

    public mutating func update(_ id: AutomationRun.ID, _ change: (inout AutomationRun) -> Void) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        change(&runs[index])
    }

    public mutating func noteHandled(_ key: String) {
        handledEvents.insert(key)
        if handledEvents.count > Self.handledEventLimit {
            handledEvents = Set(handledEvents.shuffled().prefix(Self.handledEventLimit / 2))
        }
    }
}
