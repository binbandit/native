import NativeCommands
import SwiftUI

extension CommandID {
    static let appRestartBackgroundHost: Self = "app.restartBackgroundHost"
}

extension NativeCommand {
    static func restartBackgroundHost(_ host: DurableHost, settings: SettingsPresentation) -> NativeCommand {
        NativeCommand(
            .appRestartBackgroundHost, title: "Restart Background Host…", category: .general,
            systemImage: "arrow.clockwise", keywords: ["restart", "background", "host", "this mac"]
        ) { context in
            context.openMainWindow()
            settings.open(.background, revealing: BackgroundSettingsPage.restartRow)
            host.requestHostRestart()
        }
        .available { _ in host.canRequestHostRestart }
    }
}

struct HostRestartCommands: Commands {
    let menu: CommandMenuContext

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            CommandMenuItem(.appRestartBackgroundHost, in: menu)
        }
    }
}
