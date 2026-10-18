import SwiftUI
import Terminal

extension View {
    /// Adds the task's terminal panel under this view: the transcript and composer above, the
    /// terminal below, with a divider to resize it. ⌃` shows and hides it (`TerminalCommands`).
    func terminalPanel(for session: SessionModel) -> some View {
        modifier(TerminalPanelModifier(session: session))
    }
}

private struct TerminalPanelModifier: ViewModifier {
    let session: SessionModel
    @Environment(TerminalStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsAccentPalette) private var palette
    @Environment(\.dsTransparency) private var transparency
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var availableHeight: CGFloat = 0

    func body(content: Content) -> some View {
        let panel = store.panel(for: session)
        VStack(spacing: 0) {
            content
            if panel.isVisible {
                TerminalPanel(panel: panel, store: store, maxHeight: maxPanelHeight)
                    .transition(.move(edge: .bottom))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { availableHeight = $0 }
        // The pointer and touch way in, beside ⌃` and View ▸ Show Terminal.
        .toolbar {
            ToolbarItem {
                Button {
                    store.toggle(for: session)
                } label: {
                    Image(systemName: "apple.terminal")
                }
                .help(panel.isVisible ? "Hide Terminal (⌃`)" : "Show Terminal (⌃`)")
                .accessibilityLabel(panel.isVisible ? "Hide Terminal" : "Show Terminal")
            }
        }
        .animation(.dsPanel, value: panel.isVisible)
        // Reported whether or not the panel shows, so a terminal opened from the menu starts in
        // the right colors.
        .onChange(of: appearanceKey, initial: true) { _, key in
            let appearance = TerminalAppearance(key.colorScheme)
            store.setAppearance(
                appearance, chrome: .designSystem(appearance: appearance, palette: key.palette),
                transparency: key.transparency)
        }
    }

    /// The transcript and composer keep at least this much room.
    private var maxPanelHeight: CGFloat {
        max(TerminalPanel.minHeight, availableHeight - TerminalPanel.minContentAbove)
    }

    private var appearanceKey: TerminalAppearanceKey {
        TerminalAppearanceKey(
            colorScheme: colorScheme, palette: palette,
            transparency: TerminalTransparency(transparency, reduceTransparency: reduceTransparency))
    }
}
