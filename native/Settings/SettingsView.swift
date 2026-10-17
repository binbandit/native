import SwiftUI

/// The separate Settings window, until the main window presents `SettingsScreen` itself. Delete it
/// with the `Settings` scene.
struct SettingsView: View {
    var additionalPanes: [SettingsPane] = []

    @State private var pane: SettingsPane.ID? = .general

    var body: some View {
        SettingsScreen(pane: $pane, additionalPanes: additionalPanes)
            // There's nowhere to go back to in a window of its own, so Back reopens General.
            .onChange(of: pane) {
                if pane == nil {
                    pane = .general
                }
            }
    }
}
