import Foundation

struct TaskWellToolDetail {
    /// The one thing the user can do instead of an unavailable tool, under its reason.
    struct Recovery {
        let title: String
        let action: () -> Void
    }

    var text = ""
    var stats: DiffStats?
    var isSelected = false
    var isRunning = false
    /// Its last run failed.
    var hasFailed = false
    var runningSince: Date?
    var unavailableReason: String?
    var note: String?
    var isManaged = false
    var recovery: Recovery?
}
