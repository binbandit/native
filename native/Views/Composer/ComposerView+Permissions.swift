import ACP
import SwiftUI

extension ComposerView {
    func agentChangeReceipt(_ change: ComposerAgentChange) -> some View {
        let settings = ComposerSettings(session.configOptions)
        return ComposerAgentReceiptSection(change: change) {
            if composerNext {
                settingsOpenedByCommand = false
                settingsOpenedForPermissions = true
                isModelPickerOpen = true
            } else {
                // The classic model picker has no permission choices. Reuse its autonomy picker.
                isPermissionPickerOpen = true
            }
        }
        .popover(isPresented: $isPermissionPickerOpen, arrowEdge: .bottom) {
            if let autonomy = settings.autonomy, !settings.autonomyLevels.isEmpty {
                AutonomyPicker(
                    setting: autonomy, levels: settings.autonomyLevels,
                    level: settings.shownAutonomyLevel(resumed: autonomyBeforePlan),
                    isSuspended: settings.isAutonomySuspended, agentName: session.agentName, onSet: set,
                    dismiss: { isPermissionPickerOpen = false }
                )
                .dsPopoverBackground()
            }
        }
    }
}
