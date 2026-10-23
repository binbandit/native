import ACP
import SwiftUI

/// Presentation data shared by the toolbar and its open tools panel.
struct TaskWellContent: Equatable {
    var status: TaskStatus
    var agent: String
    var verb: String = ""
    var object: String?
    var progress: TaskActivity.Progress?
    var outcome: TurnSummary?
    var showsReview = false

    var isWaiting: Bool { status.needsAttention }

    var accessibilityText: String {
        var parts = [agent, verb, object].compactMap { $0 }.filter { !$0.isEmpty }
        if let outcome {
            parts.append(
                "Changed \(outcome.changedFiles.count) files, +\(outcome.linesAdded), -\(outcome.linesRemoved)")
        }
        if let progress { parts.append("\(progress.completed) of \(progress.total) plan steps") }
        if showsReview { parts.append("Review") }
        return parts.joined(separator: ", ")
    }
}
