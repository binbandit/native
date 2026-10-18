import SwiftUI

/// The Settings pages other features contribute, in one place, so presenting Settings never needs
/// to know about them. A feature adds its pane here (one line) rather than in `NativeApp` or
/// `RootView`; Settings orders them by their group and order.
enum AppSettingsPanes {
    static func all(plugins: PluginRegistry, terminals: TerminalStore, keepAwake: KeepAwakeController) -> [SettingsPane]
    {
        [
            .labs, .git, .mcpServers(registry: plugins), .skills(registry: plugins), .terminal(terminals),
            .sounds(), .keepAwake(keepAwake), .updates, .usage(registry: plugins), .notifications, .pairedDevices,
            .celebrations(registry: plugins),
        ]
        // Labs goes away when the organization turns experiments off.
        .filter { $0.id != .labs || PolicyCenter.shared.policy.labsEnabled }
    }
}
