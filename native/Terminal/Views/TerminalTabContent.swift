import SwiftUI
import Terminal

/// The selected tab: its terminal, with what happened laid over it when the shell ended, or the
/// state that replaces it when there's no terminal to show.
struct TerminalTabContent: View {
    let panel: TerminalPanelModel
    let tab: TerminalTabList.Tab

    var body: some View {
        switch tab.status {
        case .running:
            surface
        case .exited:
            surface.overlay(alignment: .bottom) {
                NoticeBanner(
                    tone: .info,
                    systemImage: "checkmark.circle",
                    title: "The shell exited",
                    detail: "Press any key to close this tab, or start a new shell here."
                ) {
                    Button("Restart Shell") { panel.restart(tab.id) }
                        .buttonStyle(.ds(.secondary))
                }
                .padding(DS.Space.md)
            }
        case .failedToStart(.exitedImmediately):
            // The shell's own error output stays visible above.
            surface.overlay(alignment: .bottom) {
                ErrorState(
                    "The shell didn't start",
                    suggestion: "It quit as soon as it launched; its output is above. Check your shell and its "
                        + "startup files, then try again.",
                    primary: .init("Try Again") { panel.restart(tab.id) },
                    secondary: .init("Close Tab") { panel.close(tab.id) }
                )
                .padding(DS.Space.md)
            }
        case .failedToStart(.directoryMissing):
            ErrorState(
                "This task's folder is gone",
                suggestion: "\(panel.workingDirectory.abbreviatedPath) no longer exists, so the terminal can't "
                    + "start there.",
                primary: .init("Open in Home Folder") { panel.restart(tab.id, in: .homeDirectory) },
                secondary: .init("Close Tab") { panel.close(tab.id) },
                layout: .pane
            )
        case .failedToStart(.engineFailed):
            ErrorState(
                "The terminal couldn't start",
                suggestion: "Try again. If it keeps failing, quit and reopen Native.",
                primary: .init("Try Again") { panel.restart(tab.id) },
                secondary: .init("Close Tab") { panel.close(tab.id) },
                layout: .pane
            )
        }
    }

    @ViewBuilder private var surface: some View {
        #if os(macOS)
        if let surface = panel.surface(for: tab.id) {
            TerminalSurfaceHost(surface: surface)
        }
        #endif
    }
}
