import Foundation
import SwiftUI

/// The tasks item in the shared task vocabulary (`SessionModel.taskStatus`), off until it's checked
/// in the running app: `-statusBar.taskStates YES` turns it on. Off, the item and its counts are
/// as they were. Remove this switch, and `LegacyTasksSegment`, once it's verified.
enum StatusBarTaskStates {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "statusBar.taskStates")
    }

    /// The item's status for a task as it was before: what it waits for, else working while it's on
    /// a turn, else nothing.
    static func legacyStatus(of session: SessionModel) -> TaskStatus? {
        switch session.wait {
        case .input: .needsInput
        case .permission: .needsPermission
        case .planReview: .needsPlanReview
        case nil: session.phase == .prompting ? .working : nil
        }
    }
}

/// The tasks item as it was before `StatusBarTaskStates`.
struct LegacyTasksSegment: View {
    let source: any StatusBarSource

    var body: some View {
        let tasks = source.statusBarTasks
        let working = tasks.filter { !$0.needsAttention }
        let waiting = tasks.filter(\.needsAttention)
        HStack(spacing: DS.Space.xs) {
            StatusBarSegment(
                help: working.isEmpty
                    ? "No agent is working on a task."
                    : "\(working.count == 1 ? "1 task" : "\(working.count) tasks") working. Click to see them.",
                accessibilityLabel: "Working tasks",
                accessibilityValue: working.isEmpty ? "None" : "\(working.count)"
            ) {
                HStack(spacing: DS.Space.sm) {
                    if working.isEmpty {
                        StatusIndicator(status: .idle, size: StatusBarMetrics.statusGlyph)
                        Text(waiting.isEmpty ? "No tasks running" : "None working")
                            .foregroundStyle(.dsTextTertiary)
                    } else {
                        StatusIndicator(status: .working, size: StatusBarMetrics.statusGlyph)
                        Text("\(working.count) working")
                        if let start = working.compactMap(\.since).min() {
                            ElapsedTimeText(since: start)
                                .foregroundStyle(.dsTextTertiary)
                        }
                    }
                }
            } details: {
                TasksPanel(source: source)
            }
            if let first = waiting.first {
                Button {
                    source.showTask(first.id)
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        StatusIndicator(status: first.status, size: StatusBarMetrics.statusGlyph)
                        Text("\(waiting.count) \(waiting.count == 1 ? "needs" : "need") you")
                    }
                }
                .buttonStyle(.statusBarSegment(.attention))
                .help("\(first.title) · \(first.status.label). Click to open it.")
                .accessibilityLabel("Tasks that need you")
                .accessibilityValue("\(waiting.count). First: \(first.title), \(first.status.label)")
                .accessibilityHint("Opens the first one")
            }
        }
    }
}
