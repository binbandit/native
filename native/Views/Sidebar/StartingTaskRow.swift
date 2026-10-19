import SwiftUI

/// A task whose session is on its way: listed from the click on, first in its project, with the step
/// it's on in its tooltip. A failed one turns red and offers Retry and Discard here and in the
/// detail column.
struct StartingTaskRow: View {
    @Environment(AppModel.self) private var model
    let task: StartingTask

    var body: some View {
        TaskRow(
            title: title,
            status: task.failure == nil ? .starting : .failed,
            isSelected: model.selection == task.id,
            badge: nil,
            leading: AgentIcon(agent: task.agent),
            accessory: Text(task.failure == nil ? "Starting…" : "Couldn't start")
                .font(.dsCaption)
                .foregroundStyle(task.failure == nil ? .dsTextTertiary : .dsDanger)
                .lineLimit(1),
            action: { model.selection = task.id }
        )
        .help(tooltip)
        .contextMenu {
            if task.failure != nil {
                Button("Retry") { Task { await model.retry(task) } }
            }
            Button(task.failure == nil ? "Cancel" : "Discard", role: .destructive) { model.discard(task) }
        }
        .accessibilityLabel("\(title), \(task.failure?.title ?? "\(task.stepLabel)")")
        .accessibilityActions {
            if task.failure != nil {
                Button("Retry") { Task { await model.retry(task) } }
            }
            Button(task.failure == nil ? "Cancel" : "Discard") { model.discard(task) }
        }
    }

    /// The draft's first line once there is one, so a task named by what it's for shows that.
    private var title: String {
        let line = task.draft.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        return line?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "New Session"
    }

    private var tooltip: String {
        let state = task.failure.map { "\($0.title): \($0.message)" } ?? "\(task.stepLabel)…"
        return "\(task.agent.displayName) · \(state)"
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
