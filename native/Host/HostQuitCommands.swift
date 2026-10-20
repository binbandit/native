import NativeCommands
import SwiftUI

#if os(macOS)
import AppKit
#endif

extension CommandID {
    static let appQuitAndStopAgents: Self = "app.quitAndStopAgents"
}

#if os(macOS)
extension NativeCommand {
    /// Native ▸ Quit Native and Stop Agents (⌃⌥⌘Q, docs/keyboard.md). ⌘Q leaves the background
    /// host working; this quits and stops it too: running turns end as stopped by the user.
    static func quitAndStopAgents(_ host: DurableHost) -> NativeCommand {
        NativeCommand(
            .appQuitAndStopAgents, title: "Quit Native and Stop Agents", category: .general, systemImage: "stop.circle",
            keywords: ["quit", "stop", "agents", "background", "host", "exit"]
        ) { _ in
            host.stopAgentsOnQuit()
            NSApplication.shared.terminate(nil)
        }
        // Otherwise agents already stop with the app, and ⌘Q is all it takes.
        .available { _ in host.placement.outlivesApp }
    }
}

/// The Native menu's Quit Native and Stop Agents, right after Quit, while agents would outlive the
/// app.
struct HostQuitCommands: Commands {
    let host: DurableHost
    let menu: CommandMenuContext

    var body: some Commands {
        CommandGroup(after: .appTermination) {
            if host.placement.outlivesApp {
                CommandMenuItem(.appQuitAndStopAgents, in: menu)
            }
        }
    }
}
#endif
