import SwiftUI

/// How many tasks are working, for how long the longest has been at it, and how many need the
/// user, across every project, in the words every surface uses (`SessionModel.taskStatus`).
/// "Working" opens the list; "needs you" goes straight to the first task waiting, the one ⌘Y would
/// answer. A task waiting on the user isn't working, so while that's all there is, the bar shows
/// only "needs you". In a narrow window both shorten to their glyph and count.
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
        let working = tasks.filter { $0.status == .working }
        let waiting = tasks.filter(\.needsAttention)
        if working.isEmpty && waiting.isEmpty {
            // Nothing to shorten to: in a narrow window, "nothing's happening" is the first to go.
            NoTasksSegment(source: source)
        } else {
            parts(working: working, waiting: waiting, isCompact: false)
                .statusBarCompactForm {
                    parts(working: working, waiting: waiting, isCompact: true)
                }
        }
    }

    private func parts(working: [TaskActivity], waiting: [TaskActivity], isCompact: Bool) -> some View {
        HStack(spacing: DS.Space.xs) {
            if !working.isEmpty {
                WorkingTasksSegment(source: source, working: working, isCompact: isCompact)
            }
            if let first = waiting.first {
                NeedsYouButton(source: source, first: first, count: waiting.count, isCompact: isCompact)
            }
        }
    }
}

/// "No tasks running", which opens the empty list.
private struct NoTasksSegment: View {
    let source: any StatusBarSource

    var body: some View {
        StatusBarSegment(
            help: "No agent is working on a task, and none needs you.",
            accessibilityLabel: "Working tasks",
            accessibilityValue: "None"
        ) {
            HStack(spacing: DS.Space.sm) {
                StatusIndicator(status: .idle, size: StatusBarMetrics.statusGlyph)
                Text("No tasks running")
                    .foregroundStyle(.dsTextTertiary)
            }
        } details: {
            TasksPanel(source: source)
        }
    }
}

/// "2 working 1m 12s": the working loader, how many tasks are on a turn and how long the longest
/// has been at it. Compact, the loader and the count. Opens the list.
private struct WorkingTasksSegment: View {
    let source: any StatusBarSource
    let working: [TaskActivity]
    let isCompact: Bool

    var body: some View {
        StatusBarSegment(
            help: "\(working.count == 1 ? "1 task" : "\(working.count) tasks") working. Click to see them.",
            accessibilityLabel: "Working tasks",
            accessibilityValue: "\(working.count)"
        ) {
            HStack(spacing: DS.Space.sm) {
                StatusIndicator(status: .working, size: StatusBarMetrics.statusGlyph)
                Text(isCompact ? "\(working.count)" : "\(working.count) working")
                // The longest-running turn: the one most likely to need a look.
                if !isCompact, let start = working.compactMap(\.since).min() {
                    ElapsedTimeText(since: start)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
        } details: {
            TasksPanel(source: source)
        }
    }
}

/// "1 needs you", in the bar's one attention box, led by what the first task waits for (a
/// question, an approval, a plan). Compact, the glyph and the count. Opens that first task.
private struct NeedsYouButton: View {
    let source: any StatusBarSource
    let first: TaskActivity
    let count: Int
    let isCompact: Bool

    var body: some View {
        Button {
            source.showTask(first.id)
        } label: {
            HStack(spacing: DS.Space.sm) {
                StatusIndicator(status: first.status, size: StatusBarMetrics.statusGlyph)
                Text(isCompact ? "\(count)" : "\(count) \(count == 1 ? "needs" : "need") you")
            }
        }
        .buttonStyle(.statusBarSegment(.attention))
        .help(tooltip)
        .accessibilityLabel("Tasks that need you")
        .accessibilityValue("\(count). First: \(first.title), \(first.status.label)")
        .accessibilityHint("Opens the first one")
    }

    private var tooltip: String {
        let task = "\(first.title) · \(first.status.label)"
        return count == 1 ? "\(task). Click to open it." : "\(count) tasks need you. Click to open the first: \(task)."
    }
}

#if DEBUG
#Preview("Tasks item - States") {
    // Nothing; working; waiting only (no "None working" beside it); both; several waiting.
    let sources = [
        TasksPreviewSource(),
        TasksPreviewSource(working: 2),
        TasksPreviewSource(waiting: [.needsPermission]),
        TasksPreviewSource(working: 2, waiting: [.needsPermission]),
        TasksPreviewSource(working: 1, waiting: [.needsInput, .needsPermission, .needsPlanReview]),
    ]
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ForEach(sources.indices, id: \.self) { index in
                StatusBarSurface {
                    TasksStatusItem(source: sources[index]).content
                } trailing: {
                    EmptyView()
                }
            }
        }
        .frame(width: 520)
    }
}

#Preview("Tasks item - Shortening") {
    // Full while everything fits, then glyph and count, and only then gone.
    let source = TasksPreviewSource(working: 2, waiting: [.needsPermission])
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach([CGFloat(420), 300, 160], id: \.self) { width in
                StatusBarSurface {
                    TasksStatusItem(source: source).content
                } trailing: {
                    HStack(spacing: DS.Space.xs) {
                        StatusBarGlyph("memorychip")
                        Text("Native 212 MB 1.4%")
                    }
                    .statusBarSegment()
                }
                .frame(width: width)
            }
        }
    }
}
#endif
