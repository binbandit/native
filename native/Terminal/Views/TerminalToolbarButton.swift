import SwiftUI
import Terminal

/// The task's terminal entry point keeps its tabs and their activity visible when the panel hides.
struct TerminalToolbarButton: View {
    let activity: TerminalActivitySummary
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "apple.terminal")
                    .font(.dsCaption)
                if activity.openCount > 0 {
                    Text("\(activity.openCount)")
                        .monospacedDigit()
                }
                if activity.runningCount > 0 {
                    TaskSignal(status: .working, placement: .toolbarCount)
                }
                if activity.failedCount > 0 {
                    TaskSignal(status: .failed, placement: .toolbarCount)
                    Text(activity.failedCount == 1 ? "Failed" : "\(activity.failedCount) failed")
                        .foregroundStyle(.dsDanger)
                }
            }
        }
        .buttonStyle(.header(isOn: isVisible, iconOnly: activity.openCount == 0))
        .accessibilityLabel(title)
        .accessibilityValue(detail)
        .accessibilityAddTraits(isVisible ? .isSelected : [])
        .help("\(CommandRegistry.shared.help(title, for: .terminalToggle)). \(detail)")
    }

    private var title: String { isVisible ? "Hide Terminal" : "Show Terminal" }

    private var detail: String {
        guard activity.openCount > 0 else { return "No terminals open" }
        var parts = [activity.openCount == 1 ? "1 terminal open" : "\(activity.openCount) terminals open"]
        if activity.runningCount > 0 { parts.append("\(activity.runningCount) running") }
        if activity.failedCount > 0 { parts.append("\(activity.failedCount) failed") }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Terminal toolbar - Closed, idle, running and failed") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach([false, true], id: \.self) { visible in
                TerminalToolbarButton(activity: TerminalTabList().activity, isVisible: visible) {}
                TerminalToolbarButton(activity: TerminalToolbarPreviewFixtures.idle, isVisible: visible) {}
                TerminalToolbarButton(activity: TerminalToolbarPreviewFixtures.running, isVisible: visible) {}
                TerminalToolbarButton(activity: TerminalToolbarPreviewFixtures.failed, isVisible: visible) {}
                TerminalToolbarButton(activity: TerminalToolbarPreviewFixtures.mixed, isVisible: visible) {}
            }
        }
        .padding(DS.Space.lg)
    }
}
#endif
