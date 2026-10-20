import SwiftUI
import Terminal

/// The terminal's selected tab as a session tool's pane, sized by its place; the place's strip
/// lists the tabs, so the terminal's own tab bar stays out.
struct SessionTerminalPane: View {
    let panel: TerminalPanelModel
    let store: TerminalStore

    var body: some View {
        VStack(spacing: 0) {
            if case .ghosttyInvalid(_, let diagnostics) = store.configStatus {
                TerminalConfigNotice(diagnostics: diagnostics, reload: store.reloadGhosttyConfig)
                    .padding(.top, DS.Space.xs)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.dsSurfaceSunken)
        .confirmationDialog(
            "Close this terminal?", isPresented: isConfirmingClose, titleVisibility: .visible,
            presenting: panel.confirmingClose
        ) { id in
            Button("Close Terminal", role: .destructive) { panel.close(id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("A program is still running in it, and closing the terminal ends it.")
        }
    }

    @ViewBuilder private var content: some View {
        switch store.availability {
        case .available:
            if let tab = panel.tabs.selected {
                TerminalTabContent(panel: panel, tab: tab, backgroundOpacity: store.backgroundOpacity)
            } else {
                EmptyStateView(
                    "No terminal open", systemImage: "apple.terminal", message: "A shell in this task's folder."
                ) {
                    Button("New Terminal") { panel.newTab() }
                        .buttonStyle(.ds(.secondary))
                }
            }
        case .notBuilt:
            TerminalUnavailableView()
        case .failed(let reason):
            ErrorState(
                "The terminal couldn't start", recovery: reason, suggestion: "Quit and reopen Native to try again.",
                layout: .pane)
        }
    }

    private var isConfirmingClose: Binding<Bool> {
        Binding(get: { panel.confirmingClose != nil }, set: { if !$0 { panel.confirmingClose = nil } })
    }
}
