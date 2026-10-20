import SessionTools
import SwiftUI
import Terminal

/// Keeps the task's terminal in step with the session screen: ⌃`, View ▸ Show Terminal and a
/// run's Show set the panel's visibility, which opens or closes the Terminal tool, and the other way
/// round; and the terminal takes the window's colors whether or not it shows, so one opened from
/// the menu starts right.
struct SessionTerminalCompanion: View {
    let panel: TerminalPanelModel
    let store: TerminalStore
    let screen: SessionToolsScreenModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsAccentPalette) private var palette
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.dsTransparency) private var transparency
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
            .onChange(of: panel.isVisible, initial: true) { _, isVisible in
                if isVisible, !screen.isOpen(.terminal) {
                    screen.open(.terminal)
                } else if !isVisible, screen.isOpen(.terminal) {
                    screen.close(.terminal)
                }
            }
            .onChange(of: screen.isOpen(.terminal)) { _, isOpen in
                if isOpen, !panel.isVisible {
                    panel.show()
                } else if !isOpen, panel.isVisible {
                    panel.hide()
                }
            }
            .onChange(of: appearanceKey, initial: true) { _, key in
                let appearance = TerminalAppearance(key.colorScheme)
                store.setAppearance(
                    appearance,
                    chrome: .designSystem(
                        appearance: appearance, palette: key.palette, lightTone: key.lightTone, darkTone: key.darkTone),
                    transparency: key.transparency)
            }
    }

    private var appearanceKey: TerminalAppearanceKey {
        TerminalAppearanceKey(
            colorScheme: colorScheme, palette: palette, lightTone: lightTone, darkTone: darkTone,
            transparency: TerminalTransparency(
                transparency, reduceTransparency: reduceTransparency,
                isTrueBlack: colorScheme == .dark && darkTone == .trueBlack))
    }
}
