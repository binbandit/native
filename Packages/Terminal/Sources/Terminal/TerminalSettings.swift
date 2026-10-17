/// How much output a terminal keeps above the screen.
public enum TerminalScrollback: Hashable, Sendable, CaseIterable, Identifiable {
    case lines(Int)
    case unlimited

    public static let allCases: [TerminalScrollback] = [
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
    /// A `TerminalTheme` id.
    public var themeID: String

    public init(
        fontFamily: String? = nil, fontSize: Double = Self.defaultFontSize,
        scrollback: TerminalScrollback = .default, themeID: String = TerminalTheme.native.id
    ) {
        self.fontFamily = fontFamily.flatMap { $0.isEmpty ? nil : $0 }
        self.fontSize = Self.clamp(fontSize)
        self.scrollback = scrollback
        self.themeID = themeID
    }

    private static func clamp(_ size: Double) -> Double {
        min(max(size.rounded(), fontSizes.lowerBound), fontSizes.upperBound)
    }
}
