import ACP
import SwiftUI

/// The Help menu's own items: Keyboard Shortcuts, the protocol's docs, and every version on one
/// line. The status bar's "?" opens the same shortcuts sheet; signing in to and restarting agents
/// live in Settings ▸ Agents and on Home.
struct HelpCommands: Commands {
    let menu: CommandMenuContext
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .help) {
            CommandMenuItem(.helpKeyboardShortcuts, in: menu)
            Link("Agent Client Protocol Docs", destination: Self.protocolDocs)
            Divider()
            Text(versions)
        }
    }

    private static let protocolDocs = URL(string: "https://agentclientprotocol.com") ?? URL(filePath: "/")

    /// "Native 1.0 · Claude Code 2.1.3 · Codex 0.40", so a bug report can quote every version at once.
    private var versions: String {
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let agents = model.agents.map { runtime in
            [runtime.agent.displayName, runtime.info?.version ?? "…"].joined(separator: " ")
        }
        return (["Native \(app ?? "…")"] + agents).joined(separator: " · ")
    }
}
