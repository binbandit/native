import ACP
import Foundation
import SwiftUI

/// Presentation data shared by the toolbar and its open tools panel.
struct TaskWellContent: Equatable {
    var status: TaskStatus
    var agent: String
    var verb: String = ""
    var object: String?
    /// The object is code (a file, a command), set in code type; names (agents) aren't.
    var objectIsCode = true
    var progress: TaskActivityNarration.Progress?
    var outcome: TurnSummary?
    var showsReview = false
    /// A key that leaves what the well is narrating ("esc" while comparing), at its trailing edge.
    var exitKey: String?
    var attentionSince: Date?

    var isWaiting: Bool { status.needsAttention }

    var accessibilityText: String {
        var parts = [agent, verb, object].compactMap { $0 }.filter { !$0.isEmpty }
        if let outcome {
            parts.append(
                "Changed \(outcome.changedFiles.count) files, +\(outcome.linesAdded), -\(outcome.linesRemoved)")
        }
        if let progress { parts.append("\(progress.completed) of \(progress.total) plan steps") }
        if showsReview { parts.append("Review") }
        if let exitKey { parts.append("\(exitKey) to go back") }
        return parts.joined(separator: ", ")
    }
}
