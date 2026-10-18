import SwiftUI

/// How many tasks are working, for how long the longest has been at it, and how many wait on the
/// user, across every project. "Working" opens the list; "needs you" goes
/// straight to the first task waiting, the one ⌘Y would answer.
struct TasksStatusItem: StatusBarItem {
    let source: any StatusBarSource

    let id = "tasks"
    let title = "Tasks"
    let placement = StatusBarPlacement.leading
    let order = 50

    var content: some View {
        TasksSegment(source: source)
    }
}

private struct TasksSegment: View {
    let source: any StatusBarSource

    var body: some View {
        let tasks = source.statusBarTasks
        let working = tasks.filter { !$0.needsAttention }
        let waiting = tasks.filter(\.needsAttention)
        HStack(spacing: DS.Space.xs) {
            StatusBarSegment(
                help: working.isEmpty
                    ? "No agent is working on a task."
                    : "\(Self.count(working.count, "task")) working. Click to see them.",
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
                        // The longest-running turn: the one most likely to need a look.
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

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }
}
