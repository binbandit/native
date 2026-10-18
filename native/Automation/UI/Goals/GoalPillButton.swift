import NativeAutomation
import SwiftUI

/// The composer's goal control: "Goal" to set one, or the goal's status once there is one, filled
/// while the goal is driving the agent (the way pills mark a non-default mode).
struct GoalPillButton: View {
    let status: GoalStatus?
    /// Only the target, when the composer is short of room; the status stays in the tooltip and the
    /// accessibility label.
    var showsIcon = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "target")
        }
        .buttonStyle(.pill(isOn: status == .active, isSquare: showsIcon))
        .help(CommandRegistry.shared.help(status == nil ? "Set a goal for the agent to work toward" : "Edit the goal", for: .goalEdit))
        .accessibilityLabel(status == nil ? "Set Goal" : "Goal, \(status?.label ?? "")")
    }

    private var title: String {
        guard let status else { return "Goal" }
        return status == .active ? "Goal" : "Goal · \(status.label)"
    }
}
