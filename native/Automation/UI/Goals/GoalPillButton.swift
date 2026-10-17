import SwiftUI

/// The composer's goal control: "Goal" to set one, or the goal's status once there is one, filled
/// while the goal is driving the agent (the way Factory marks a non-default mode).
struct GoalPillButton: View {
    let status: GoalStatus?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "target")
        }
        .buttonStyle(.pill(isOn: status == .active))
        .help(status == nil ? "Set a goal for the agent to work toward (⌥⌘G)" : "Edit the goal (⌥⌘G)")
        .accessibilityLabel(status == nil ? "Set Goal" : "Goal, \(status?.label ?? "")")
    }

    private var title: String {
        guard let status else { return "Goal" }
        return status == .active ? "Goal" : "Goal · \(status.label)"
    }
}
