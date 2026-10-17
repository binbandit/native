/// Light or dark, the two appearances every terminal theme covers.
public enum TerminalAppearance: Hashable, Sendable {
    case light
    case dark
}

/// The colors around the text: background, default text, cursor and selection.
public struct TerminalChrome: Hashable, Sendable {
    public var background: TerminalRGB
    public var foreground: TerminalRGB
    public var cursor: TerminalRGB
    /// Text under a block cursor.
    public var cursorText: TerminalRGB
    public var selectionBackground: TerminalRGB

    public init(
        background: TerminalRGB, foreground: TerminalRGB, cursor: TerminalRGB, cursorText: TerminalRGB,
        selectionBackground: TerminalRGB
    ) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorText = cursorText
        self.selectionBackground = selectionBackground
    }
}

/// Everything a terminal draws with in one appearance.
public struct TerminalColors: Hashable, Sendable {
    public var chrome: TerminalChrome
    /// The 16 ANSI colors in order: black, red, green, yellow, blue, magenta, cyan, white, then the
    /// bright variant of each.
    public var palette: [TerminalRGB]

    public init(chrome: TerminalChrome, palette: [TerminalRGB]) {
        self.chrome = chrome
        self.palette = palette
    }
}

/// A terminal color theme with a light and a dark variant. Native's own theme takes its chrome from
/// the app's design system so the terminal sits in the window like the rest of the content; a code
/// theme (Dracula, Solarized, ...) brings its own chrome.
public struct TerminalTheme: Identifiable, Hashable, Sendable {
    public struct Variant: Hashable, Sendable {
        /// The 16 ANSI colors, in `TerminalColors.palette` order.
        public var palette: [TerminalRGB]
        /// The theme's own background, text, cursor and selection; `nil` follows the app.
        public var chrome: TerminalChrome?

        public init(palette: [UInt32], chrome: TerminalChrome? = nil) {
            precondition(palette.count == 16, "A terminal palette has 16 colors")
            self.palette = palette.map(TerminalRGB.init)
            self.chrome = chrome
        }
    }

    public let id: String
    public let name: String
    public let light: Variant
    public let dark: Variant

    public init(id: String, name: String, light: Variant, dark: Variant) {
        self.id = id
        self.name = name
        self.light = light
        self.dark = dark
    }

    /// The colors to draw with in `appearance`; `appChrome` is used when the theme follows the app.
    public func colors(for appearance: TerminalAppearance, appChrome: TerminalChrome) -> TerminalColors {
        let variant = appearance == .dark ? dark : light
        return TerminalColors(chrome: variant.chrome ?? appChrome, palette: variant.palette)
    }

    /// Native's theme: the app's own background and text, with ANSI colors adapted from GitHub
    /// Primer's terminal palettes (contrast-checked on light and dark), whose reds, greens, yellows,
    /// blues and purples are the design system's status hues in dark mode.
    public static let native = TerminalTheme(
        id: "native",
        name: "Native",
        light: Variant(palette: [
            0x24292F, 0xCF222E, 0x116329, 0x4D2D00, 0x0969DA, 0x8250DF, 0x1B7C83, 0x6E7781,
            0x57606A, 0xA40E26, 0x1A7F37, 0x633C01, 0x218BFF, 0xA475F9, 0x3192AA, 0x8C959F,
        ]),
        dark: Variant(palette: [
            0x484F58, 0xF87272, 0x4ADE80, 0xD29922, 0x61A6FA, 0xA371F7, 0x39C5CF, 0xB1BAC4,
            0x6E7681, 0xFFA198, 0x56D364, 0xE3B341, 0x79C0FF, 0xD2A8FF, 0x56D4DD, 0xFFFFFF,
        ])
    )

    /// Every theme, for a picker. The code-theme setting adds to this.
    public static let all: [TerminalTheme] = [.native]

    /// The theme with `id`; unknown ids get Native's.
    public static func named(_ id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? .native
    }
}
