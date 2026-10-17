import SwiftUI

/// The Settings pages other features contribute, in one place, so presenting Settings never needs
/// to know about them. A feature adds its pane here (one line) rather than in `NativeApp` or
/// `RootView`; Settings orders them by their group and order.
enum AppSettingsPanes {
    static func all(plugins: PluginRegistry) -> [SettingsPane] {
        [.labs, .git, .mcpServers(registry: plugins)]
    }
}
