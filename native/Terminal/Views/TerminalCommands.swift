import NativeCommands
import SwiftUI
import Terminal

extension CommandID {
    static let terminalToggle: Self = "terminal.toggle"
    static let terminalNewTab: Self = "terminal.newTab"
    static let terminalRetryJob: Self = "terminal.retryJob"
    static let terminalStopJob: Self = "terminal.stopJob"
    static let terminalCloseTab: Self = "terminal.closeTab"
}

extension NativeCommand {
    /// Show Terminal, New Terminal Tab and Close Terminal Tab, for the task in the frontmost window.
    /// Their keys are in `docs/keyboard.md`, Terminal.
    static func terminal(_ store: TerminalStore) -> [NativeCommand] {
        func panel(_ context: CommandContext) -> TerminalPanelModel? {
            context.session.map(store.panel(for:))
        }
        return [
            NativeCommand(.terminalToggle, title: "Show or Hide Terminal", category: .terminal, systemImage: "terminal")
            {
                guard let session = $0.session else { return }
                store.toggle(for: session)
            }
            .menuTitle { panel($0)?.isVisible == true ? "Hide Terminal" : "Show Terminal" }
            .available { $0.session != nil },

            NativeCommand(
                .terminalNewTab, title: "New Terminal Tab", category: .terminal, systemImage: "plus.rectangle"
            ) {
                guard let session = $0.session else { return }
                store.newTab(for: session)
            }
            .available { $0.session != nil && store.availability == .available },

            NativeCommand(
                .terminalRetryJob, title: "Retry Terminal Command", category: .terminal, systemImage: "arrow.clockwise"
            ) {
                guard let panel = panel($0), let id = panel.tabs.selectedID else { return }
                panel.rerunJob(in: id)
            }
            .available { panel($0)?.tabs.selected?.job?.isRunning == false },

            NativeCommand(.terminalStopJob, title: "Stop Terminal Command", category: .terminal, systemImage: "stop") {
                guard let panel = panel($0), let id = panel.tabs.selectedID else { return }
                panel.stopJob(in: id)
            }
            .available { panel($0)?.tabs.selected?.job?.isRunning == true },

            NativeCommand(
                .terminalCloseTab, title: "Close Terminal Tab", category: .terminal, systemImage: "xmark.rectangle"
            ) {
                guard let panel = panel($0), let id = panel.tabs.selectedID else { return }
                panel.requestClose(id)
            }
            .available { panel($0)?.isVisible == true && panel($0)?.tabs.selectedID != nil },
        ]
    }

    /// Whether the visible task's terminal has keyboard focus, so commands that share a key with the
    /// terminal's own bindings (the palette's ⌘K is the terminal's Clear) can step aside.
    static func terminalHasFocus(_ store: TerminalStore, in context: CommandContext) -> Bool {
        context.session.map { store.panel(for: $0).isFocused } ?? false
    }
}

/// View ▸ Show Terminal, New Terminal Tab and Close Terminal Tab.
struct TerminalCommands: Commands {
    let menu: CommandMenuContext

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            CommandMenuItem(.terminalToggle, in: menu)
            CommandMenuItem(.terminalNewTab, in: menu)
            CommandMenuItem(.terminalCloseTab, in: menu)
            CommandMenuItem(.terminalRetryJob, in: menu)
            CommandMenuItem(.terminalStopJob, in: menu)
        }
    }
}
