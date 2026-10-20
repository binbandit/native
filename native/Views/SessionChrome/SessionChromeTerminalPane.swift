#if DEBUG
import SwiftUI
import Terminal

/// The task's terminal in a chrome place, sized by the place: the terminal's own tab bar (unless
/// the place lists the tabs itself) and the selected tab.
struct SessionChromeTerminalPane: View {
    let panel: TerminalPanelModel
    let store: TerminalStore
    var showsTabBar = true

    var body: some View {
        VStack(spacing: 0) {
            if showsTabBar {
                TerminalTabBar(panel: panel, showsTabs: store.availability == .available)
                    .background(.dsSurfaceSunken.opacity(store.backgroundOpacity))
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.dsSurfaceSunken)
    }

    @ViewBuilder private var content: some View {
        switch store.availability {
        case .available:
            if let tab = panel.tabs.selected {
                TerminalTabContent(panel: panel, tab: tab, backgroundOpacity: store.backgroundOpacity)
            } else {
                EmptyStateView(
                    "No terminal open", systemImage: "apple.terminal",
                    message: "A shell in this task's folder, beside the agent's own."
                ) {
                    Button("New Terminal") { panel.newTab() }
                        .buttonStyle(.ds(.secondary))
                }
            }
        case .notBuilt:
            TerminalUnavailableView()
        case .failed(let reason):
            ErrorState(
                "The terminal couldn't start",
                recovery: reason,
                suggestion: "Quit and reopen Native to try again.",
                layout: .pane
            )
        }
    }
}
#endif
