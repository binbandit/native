import SwiftUI

/// What stands in for the recent tasks while the project has none: what goes here, and the one
/// action that starts the first.
struct HomeNoTasks<ID: Hashable>: View {
    let projectName: String
    /// The agent ⌘N starts a task with, once one is ready.
    let agent: HomeAgent<ID>?
    let onNewTask: (ID) -> Void

    var body: some View {
        EmptyStateView(
            "No tasks in \(projectName) yet",
            message: agent == nil
                ? "Your agents are still getting ready. Tasks you start here are listed here and in the sidebar."
                : "Tasks you start here, with any agent, are listed here and in the sidebar."
        ) {
            if let agent {
                Button {
                    onNewTask(agent.id)
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Text("New \(agent.name) task")
                        if let shortcut = agent.shortcut {
                            Text(shortcut.displayString)
                                .foregroundStyle(.dsTextTertiary)
                        }
                    }
                }
                .buttonStyle(.ds(.secondary, size: .medium))
            }
        }
    }
}
