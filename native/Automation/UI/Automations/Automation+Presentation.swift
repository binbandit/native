import Foundation
import NativeAutomation

extension Automation {
    /// "Every day at 9:00 AM · When CI fails on a pull request", or how to run it without triggers.
    var triggerSummary: String {
        triggers.isEmpty ? "Runs when you run it" : triggers.map(\.summary).joined(separator: " · ")
    }

    /// Its glyph in lists: paused, then whatever its latest run is doing or how it ended.
    func glyph(latest run: AutomationRun?) -> AutomationGlyph {
        if isPaused { return .task(.paused) }
        return run.map { AutomationGlyph(run: $0.status) } ?? .task(.idle)
    }
}

extension AutomationGlyph {
    init(run status: AutomationRunStatus) {
        switch status {
        case .preparing: self = .task(.starting)
        case .running: self = .task(.working)
        case .needsYou: self = .task(.needsInput)
        case .succeeded: self = .task(.done)
        case .failed: self = .task(.failed)
        case .cancelled: self = .task(.cancelled)
        case .skipped: self = .task(.idle)
        }
    }
}
