/// How much output a terminal keeps above the screen.
public enum TerminalScrollback: Hashable, Sendable, Identifiable {
    case lines(Int)
    case unlimited

    /// The limits Settings offers; an imported limit outside them is offered too.
    public static let choices: [TerminalScrollback] = [
        .lines(1000), .lines(10000), .lines(50000), .lines(100_000), .unlimited,
    ]

    public static let `default` = TerminalScrollback.lines(10000)

    public var id: Int {
        switch self {
        case .lines(let count): count
        case .unlimited: 0
        }
    }

    /// The stored form: a line count, 0 for unlimited.
    public init(storedValue: Int) {
        self = storedValue <= 0 ? .unlimited : .lines(storedValue)
    }

    public var storedValue: Int { id }
}

/// The cursor's shape, as Ghostty's `cursor-style` names them.
public enum TerminalCursorStyle: String, Hashable, Sendable, Codable, CaseIterable {
    case block
    case bar
    case underline
}

public struct TerminalCursor: Hashable, Sendable, Codable {
    public var style: TerminalCursorStyle
    public var blinks: Bool

    public init(style: TerminalCursorStyle = .block, blinks: Bool = true) {
        self.style = style
        self.blinks = blinks
    }
}

/// Which shell a terminal runs.
public enum TerminalShell: Hashable, Sendable, Codable {
    /// The user's login shell from the user database, as Terminal and Ghostty run it.
    case login
    /// A shell the user picked.
    case path(String)

    /// The shell's path, given the user's login shell.
    public func path(loginShell: String) -> String {
        switch self {
        case .login: loginShell
        case .path(let path): path
        }
    }

    /// The command libghostty runs (as a login shell, through `login(1)` and `exec -l`): the path,
    /// quoted so spaces and quotes in it survive the shell that execs it.
    public static func command(for path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// What a shell falls back to when the chosen one is missing or fails: every Mac has it.
    public static let fallback = "/bin/zsh"
}

/// Where the terminal's colors come from.
public enum TerminalColorChoice: Hashable, Sendable, Codable {
    /// The app's theme: Native's, or the code theme's terminal palette.
    case app
    /// A snapshot imported from the user's Ghostty config.
    case imported(TerminalImportedColors)
}

/// Colors copied from a Ghostty config, for each appearance (a Ghostty theme can differ by
/// appearance with `theme = light:…,dark:…`).
public struct TerminalImportedColors: Hashable, Sendable, Codable {
    /// The Ghostty theme they came from, such as "Dracula", when the config named one.
    public var themeName: String?
    public var light: TerminalColors
    public var dark: TerminalColors

    public init(themeName: String?, light: TerminalColors, dark: TerminalColors) {
        self.themeName = themeName
        self.light = light
        self.dark = dark
    }

    public func colors(for appearance: TerminalAppearance) -> TerminalColors {
        appearance == .dark ? dark : light
    }
}

/// The user's terminal preferences (Settings ▸ Terminal), independent of how they're stored or drawn.
public struct TerminalSettings: Hashable, Sendable {
    /// Sizes the font picker offers, in points.
    public static let fontSizes: ClosedRange<Double> = 9...24
    public static let defaultFontSize: Double = 12

    /// A monospaced font family, or `nil` for the app's code font.
    public var fontFamily: String?
    public var fontSize: Double {
        didSet { fontSize = Self.clamp(fontSize) }
    }
    public var scrollback: TerminalScrollback
    public var cursor: TerminalCursor
    public var colors: TerminalColorChoice
    public var shell: TerminalShell
    /// Whether terminals load the user's own Ghostty config instead of the settings above.
    public var usesGhosttyConfig: Bool

    public init(
        fontFamily: String? = nil, fontSize: Double = Self.defaultFontSize, scrollback: TerminalScrollback = .default,
        cursor: TerminalCursor = TerminalCursor(), colors: TerminalColorChoice = .app, shell: TerminalShell = .login,
        usesGhosttyConfig: Bool = false
    ) {
        self.fontFamily = fontFamily.flatMap { $0.isEmpty ? nil : $0 }
        self.fontSize = Self.clamp(fontSize)
        self.scrollback = scrollback
        self.cursor = cursor
        self.colors = colors
        self.shell = shell
        self.usesGhosttyConfig = usesGhosttyConfig
    }

    private static func clamp(_ size: Double) -> Double {
        min(max(size.rounded(), fontSizes.lowerBound), fontSizes.upperBound)
    }
}
