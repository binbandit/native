import SwiftUI

/// How many tasks are working and how many wait on the user, across every project (the reference app's
/// terminal-session count). Click for the list; a row opens its task.
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

    private var tasks: [TaskActivity] {
        source.statusBarTasks
    }

    private var working: Int {
        tasks.count { !$0.needsAttention }
    }

    private var waiting: Int {
        tasks.count(where: \.needsAttention)
    }

    /// "2 working, 1 needs you", or that nothing is running.
    private var summary: String {
        let parts = [
            working > 0 ? "\(working) working" : nil,
            waiting > 0 ? "\(waiting) \(waiting == 1 ? "needs" : "need") you" : nil,
        ].compactMap(\.self)
        return parts.isEmpty ? "No tasks running" : parts.joined(separator: ", ")
    }

    var body: some View {
        StatusBarSegment(
            help: tasks.isEmpty ? "No agent is working on a task." : "Tasks: \(summary). Click to see them.",
            accessibilityLabel: "Tasks",
            accessibilityValue: summary
        ) {
            HStack(spacing: DS.Space.sm) {
                if tasks.isEmpty {
                    StatusIndicator(status: .idle, size: StatusBarMetrics.statusGlyph)
                    Text("No tasks running")
                        .foregroundStyle(.dsTextTertiary)
                } else {
                    if working > 0 {
                        StatusIndicator(status: .working, size: StatusBarMetrics.statusGlyph)
                        Text("\(working) working")
                    }
                    if waiting > 0 {
                        StatusIndicator(status: .needsPermission, size: StatusBarMetrics.statusGlyph)
                        Text("\(waiting) \(waiting == 1 ? "needs" : "need") you")
                    }
                }
            }
        } details: {
            TasksPanel(source: source)
        }
    }
}
