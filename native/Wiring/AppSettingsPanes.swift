import NativePolicy
import SwiftUI

/// The Settings pages other features contribute, in one place, so presenting Settings never needs
/// to know about them. A feature adds its pane here (one line) rather than in `NativeApp` or
/// `RootView`; Settings orders them by their group and order.
enum AppSettingsPanes {
    static func all(
        plugins: PluginRegistry, terminals: TerminalStore, keepAwake: KeepAwakeController, projects: [Project]
    ) -> [SettingsPane] {
        [
            .labs, .git, .gitHub, .scripts, .aiInstructions, .modes(projects: projects), .mcpServers(registry: plugins),
            .skills(registry: plugins), .terminal(terminals), .sounds(), .keepAwake(keepAwake), .updates,
            .usage(registry: plugins), .notifications, .pairedDevices, .celebrations(registry: plugins), .background,
            .search(BuiltInPlugins.search.center), .hosts,
        ]
        // Labs goes away when the organization turns experiments off; Hosts stays hidden until
        // paired hosts are on.
        .filter { $0.id != .labs || PolicyCenter.shared.policy.labsEnabled }
        .filter { $0.id != .hosts || SettingsPane.showsHosts }
            + SettingsPane.projects(projects)
    }
}
