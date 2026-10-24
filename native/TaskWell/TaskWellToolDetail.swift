import Foundation

struct TaskWellToolDetail {
    var text = ""
    var stats: DiffStats?
    var isSelected = false
    var isRunning = false
    var runningSince: Date?
    var unavailableReason: String?
    var isManaged = false
}
