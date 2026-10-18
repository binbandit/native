import Foundation
import Observation
import Terminal

/// The user's terminal settings (Settings ▸ Terminal), kept in `UserDefaults` under `terminal.*`.
@Observable
final class TerminalPreferences {
    var settings: TerminalSettings {
        didSet {
            save()
            onChange?()
        }
    }

    /// The panel's height, shared by every task so it opens the size the user last left it.
    var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: Key.panelHeight) }
    }

    static let defaultPanelHeight: Double = 260

    /// Called after `settings` changes, so running terminals can restyle.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let fontFamily = "terminal.fontFamily"
        static let fontSize = "terminal.fontSize"
        static let scrollback = "terminal.scrollbackLines"
        static let cursor = "terminal.cursor"
        static let colors = "terminal.colors"
        static let usesGhosttyConfig = "terminal.usesGhosttyConfig"
        static let panelHeight = "terminal.panelHeight"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = TerminalSettings(
            fontFamily: defaults.string(forKey: Key.fontFamily),
            fontSize: defaults.object(forKey: Key.fontSize) as? Double ?? TerminalSettings.defaultFontSize,
            scrollback: (defaults.object(forKey: Key.scrollback) as? Int).map(TerminalScrollback.init(storedValue:))
                ?? .default,
            cursor: Self.decode(TerminalCursor.self, from: defaults.data(forKey: Key.cursor)) ?? TerminalCursor(),
            colors: Self.decode(TerminalColorChoice.self, from: defaults.data(forKey: Key.colors)) ?? .app,
            usesGhosttyConfig: defaults.bool(forKey: Key.usesGhosttyConfig)
        )
        panelHeight = defaults.object(forKey: Key.panelHeight) as? Double ?? Self.defaultPanelHeight
    }

    private func save() {
        defaults.set(settings.fontFamily, forKey: Key.fontFamily)
        defaults.set(settings.fontSize, forKey: Key.fontSize)
        defaults.set(settings.scrollback.storedValue, forKey: Key.scrollback)
        defaults.set(try? JSONEncoder().encode(settings.cursor), forKey: Key.cursor)
        defaults.set(try? JSONEncoder().encode(settings.colors), forKey: Key.colors)
        defaults.set(settings.usesGhosttyConfig, forKey: Key.usesGhosttyConfig)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
