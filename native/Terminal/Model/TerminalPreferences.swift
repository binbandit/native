import Foundation
import Observation
import Terminal

/// The user's terminal settings (Settings ▸ Terminal), kept in `UserDefaults` under `terminal.*`.
@Observable
final class TerminalPreferences {
    var settings: TerminalSettings {
        didSet { save() }
    }

    /// The panel's height, shared by every task so it opens the size the user last left it.
    var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: Key.panelHeight) }
    }

    static let defaultPanelHeight: Double = 260

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let fontFamily = "terminal.fontFamily"
        static let fontSize = "terminal.fontSize"
        static let scrollback = "terminal.scrollbackLines"
        static let theme = "terminal.theme"
        static let panelHeight = "terminal.panelHeight"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = TerminalSettings(
            fontFamily: defaults.string(forKey: Key.fontFamily),
            fontSize: defaults.object(forKey: Key.fontSize) as? Double ?? TerminalSettings.defaultFontSize,
            scrollback: (defaults.object(forKey: Key.scrollback) as? Int).map(TerminalScrollback.init(storedValue:))
                ?? .default,
            themeID: defaults.string(forKey: Key.theme) ?? TerminalTheme.native.id
        )
        panelHeight = defaults.object(forKey: Key.panelHeight) as? Double ?? Self.defaultPanelHeight
    }

    private func save() {
        defaults.set(settings.fontFamily, forKey: Key.fontFamily)
        defaults.set(settings.fontSize, forKey: Key.fontSize)
        defaults.set(settings.scrollback.storedValue, forKey: Key.scrollback)
        defaults.set(settings.themeID, forKey: Key.theme)
    }
}
