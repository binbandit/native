import Foundation

/// What "Import from Ghostty" copies into Native's terminal settings: a one-time snapshot of the
/// user's Ghostty config. Each field is nil when the config doesn't set it, and the setting keeps
/// Native's value.
public struct TerminalImport: Hashable, Sendable {
    public var fontFamily: String?
    public var fontSize: Double?
    public var colors: TerminalImportedColors?
    public var cursor: TerminalCursor?
    public var scrollback: TerminalScrollback?
    /// The files it was read from, in load order.
    public var files: [URL]

    public init(
        fontFamily: String? = nil, fontSize: Double? = nil, colors: TerminalImportedColors? = nil,
        cursor: TerminalCursor? = nil, scrollback: TerminalScrollback? = nil, files: [URL] = []
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.colors = colors
        self.cursor = cursor
        self.scrollback = scrollback
        self.files = files
    }

    /// Whether there's anything to import.
    public var isEmpty: Bool {
        fontFamily == nil && fontSize == nil && colors == nil && cursor == nil && scrollback == nil
    }

    /// `settings` with everything this import found copied in.
    public func applied(to settings: TerminalSettings) -> TerminalSettings {
        var result = settings
        if let fontFamily { result.fontFamily = fontFamily }
        if let fontSize { result.fontSize = fontSize }
        if let colors { result.colors = .imported(colors) }
        if let cursor { result.cursor = cursor }
        if let scrollback { result.scrollback = scrollback }
        return result
    }
}

/// Reads a `TerminalImport` from a user's Ghostty config files.
public enum GhosttyImporter {
    /// - Parameters:
    ///   - files: The config as `GhosttyConfigFile.load` read it.
    ///   - theme: The text of the theme at the first of the given paths that exists.
    public static func read(
        _ files: [GhosttyConfigFile], locations: GhosttyConfigLocations, theme: ([URL]) -> String?
    ) -> TerminalImport {
        var result = TerminalImport(files: files.map(\.url))

        // `font-family` is repeatable: an empty value starts over, and the first after that is
        // the primary face (the rest are fallbacks).
        let families = files.entries("font-family").map(\.value)
        let primary = families.split(separator: "", omittingEmptySubsequences: false).last?.first
        result.fontFamily = primary
        result.fontSize = files.lastValue("font-size").flatMap(Double.init)

        if let style = files.lastValue("cursor-style") {
            let shape: TerminalCursorStyle =
                style == "block_hollow" ? .block : TerminalCursorStyle(rawValue: style) ?? .block
            result.cursor = TerminalCursor(
                style: shape, blinks: files.lastValue("cursor-style-blink").map { $0 != "false" } ?? true)
        } else if let blink = files.lastValue("cursor-style-blink"), !blink.isEmpty {
            result.cursor = TerminalCursor(style: .block, blinks: blink != "false")
        }

        switch files.lastValue("scrollback-limit-lines") {
        case "unlimited": result.scrollback = .unlimited
        case let value?: result.scrollback = Int(value).map(TerminalScrollback.lines)
        case nil: break
        }

        result.colors = colors(files, locations: locations, theme: theme)
        return result
    }

    /// The colors for each appearance: Ghostty's defaults, then the theme for that appearance,
    /// then the colors the config sets itself, which win over the theme's as in Ghostty. Nil when
    /// the config sets neither a theme nor a color.
    static func colors(
        _ files: [GhosttyConfigFile], locations: GhosttyConfigLocations, theme: ([URL]) -> String?
    ) -> TerminalImportedColors? {
        let themeValue = files.lastValue("theme").flatMap { $0.isEmpty ? nil : $0 }
        let names = themeValue.map(ThemeNames.init)
        let own = files.flatMap(\.entries)
        guard names != nil || own.contains(where: { ColorKeys.all.contains($0.key) }) else { return nil }

        func resolve(_ name: String?) -> TerminalColors {
            var colors = ColorBuilder()
            if let name, let text = theme(locations.themeFiles(named: name)) {
                colors.apply(GhosttyConfigFile(url: URL(filePath: name), text: text).entries)
            }
            colors.apply(own)
            return colors.result
        }
        return TerminalImportedColors(
            themeName: themeValue, light: resolve(names?.light), dark: resolve(names?.dark))
    }

    /// `theme = Name` or `theme = light:Name,dark:Other`.
    struct ThemeNames {
        let light: String
        let dark: String

        init(_ value: String) {
            var light = value
            var dark = value
            for part in value.split(separator: ",") {
                let part = part.trimmingCharacters(in: .whitespaces)
                if part.hasPrefix("light:") { light = String(part.dropFirst(6)) }
                if part.hasPrefix("dark:") { dark = String(part.dropFirst(5)) }
            }
            self.light = light
            self.dark = dark
        }
    }

    enum ColorKeys {
        static let all: Set<String> = [
            "palette", "background", "foreground", "cursor-color", "cursor-text", "selection-background",
        ]
    }

    /// Folds color entries over Ghostty's defaults.
    struct ColorBuilder {
        /// Ghostty's default colors (`terminal/color.zig`, `config/Config.zig`).
        var palette: [TerminalRGB] = [
            0x1D1F21, 0xCC6666, 0xB5BD68, 0xF0C674, 0x81A2BE, 0xB294BB, 0x8ABEB7, 0xC5C8C6,
            0x666666, 0xD54E53, 0xB9CA4A, 0xE7C547, 0x7AA6DA, 0xC397D8, 0x70C0B1, 0xEAEAEA,
        ].map(TerminalRGB.init)
        var background = TerminalRGB(0x282C34)
        var foreground = TerminalRGB(0xFFFFFF)
        var cursor: TerminalRGB?
        var cursorText: TerminalRGB?
        var selection: TerminalRGB?

        mutating func apply(_ entries: [GhosttyConfigEntry]) {
            for entry in entries {
                switch entry.key {
                case "palette":
                    let parts = entry.value.split(separator: "=", maxSplits: 1)
                    if parts.count == 2, let index = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                        palette.indices.contains(index),
                        let color = TerminalRGB(hex: parts[1].trimmingCharacters(in: .whitespaces))
                    {
                        palette[index] = color
                    }
                case "background": background = TerminalRGB(hex: entry.value) ?? background
                case "foreground": foreground = TerminalRGB(hex: entry.value) ?? foreground
                case "cursor-color": cursor = TerminalRGB(hex: entry.value) ?? cursor
                case "cursor-text": cursorText = TerminalRGB(hex: entry.value) ?? cursorText
                case "selection-background": selection = TerminalRGB(hex: entry.value) ?? selection
                default: break
                }
            }
        }

        var result: TerminalColors {
            TerminalColors(
                chrome: TerminalChrome(
                    background: background,
                    foreground: foreground,
                    cursor: cursor ?? foreground,
                    cursorText: cursorText ?? background,
                    // Ghostty inverts the selection when no color is set; a tint reads better
                    // beside Native's own selections.
                    selectionBackground: selection ?? foreground.over(background, opacity: 0.28)
                ),
                palette: palette
            )
        }
    }
}
