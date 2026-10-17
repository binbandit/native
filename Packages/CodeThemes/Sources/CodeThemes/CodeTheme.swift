/// A named code color theme. Many themes exist for only one appearance, so a theme has a light palette, a dark
/// palette or both; the initializers guarantee at least one.
public struct CodeTheme: Identifiable, Sendable, Hashable {
    public struct ID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            rawValue = value
        }
    }

    public let id: ID
    public let name: String
    public let light: CodePalette?
    public let dark: CodePalette?

    public init(id: ID, name: String, light: CodePalette, dark: CodePalette) {
        self.id = id
        self.name = name
        self.light = light
        self.dark = dark
    }

    public init(id: ID, name: String, light: CodePalette) {
        self.id = id
        self.name = name
        self.light = light
        dark = nil
    }

    public init(id: ID, name: String, dark: CodePalette) {
        self.id = id
        self.name = name
        light = nil
        self.dark = dark
    }

    public func palette(for appearance: CodeAppearance) -> CodePalette? {
        switch appearance {
        case .light: light
        case .dark: dark
        }
    }

    public static let all: [CodeTheme] = [
        native,
        atomOne,
        catppuccinLatte,
        catppuccinMacchiato,
        catppuccinMocha,
        dracula,
        github,
        gruvboxDark,
        nord,
        rosePine,
        solarized,
        tokyoNight,
    ]

    public static func theme(id: ID) -> CodeTheme? {
        all.first { $0.id == id }
    }
}
