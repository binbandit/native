import NativeSetup
import SwiftUI

/// What stands in for the recent tasks while there are none: what goes here, and how to start the
/// first. Failed agents keep their Restart cards above, with Settings here if a retry doesn't help.
struct HomeNoTasks: View {
    let projectName: String
    /// The ⌘N shortcut, while an agent is ready to take it.
    let newTaskShortcut: KeyboardShortcut?
    let isAnyAgentReady: Bool
    let startupFailure: AgentStartupFailure?
    let onManageAgents: () -> Void

    var body: some View {
        if let startupFailure {
            EmptyStateView(
                startupFailure.title, message: startupFailure.message,
                actionTitle: "Agents Settings", action: onManageAgents)
        } else {
            EmptyStateView("No tasks in \(projectName) yet", message: message)
        }
    }

    private var message: String {
        guard isAnyAgentReady else {
            return "Your agents are still getting ready. Tasks you start here will be listed here."
        }
        let shortcut = newTaskShortcut.map { ", or press \($0.displayString)" } ?? ""
        return "Pick an agent above to start one\(shortcut)."
    }
}

#if DEBUG
#Preview("No tasks - All agents failed") {
    DSPreviewPair {
        HomeNoTasks(
            projectName: "native", newTaskShortcut: nil, isAnyAgentReady: false,
            startupFailure: AgentStartupFailure(agents: [("Exit Agent", .stopped), ("Second Agent", .stopped)]),
            onManageAgents: {}
        )
        .frame(width: 360)
    }
}
#endif
