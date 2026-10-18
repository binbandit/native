import AppAppearance
import SwiftUI

/// The celebrations chooser.
struct CelebrationsSettingsPage: View {
    @Environment(CelebrationCenter.self) private var center
    @Environment(PluginRegistry.self) private var plugins

    static func rowID(_ id: CelebrationID) -> SettingsRowID {
        SettingsRowID("celebration.\(id.rawValue)")
    }

    var body: some View {
        SettingsPage {
            SettingsHeader("Celebrations")
        }
    }
}
