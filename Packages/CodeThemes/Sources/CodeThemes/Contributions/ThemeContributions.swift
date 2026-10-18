/// The themes a plugin declares in its `plugin.json` (`"themes": {"code": [...], "accents": [...]}`).
/// Themes are data only: each entry is kept as written and checked on its own (`codeThemes()`,
/// `accents(lightBackgrounds:darkBackgrounds:)`), so one broken theme reports its problem without
/// taking the plugin or the other themes with it.
public struct ThemeContributions: Codable, Hashable, Sendable {
    public var code: [ThemeJSON]
    public var accents: [ThemeJSON]

    public init(code: [ThemeJSON] = [], accents: [ThemeJSON] = []) {
        self.code = code
        self.accents = accents
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent([ThemeJSON].self, forKey: .code) ?? []
        accents = try container.decodeIfPresent([ThemeJSON].self, forKey: .accents) ?? []
    }

    public var isEmpty: Bool { code.isEmpty && accents.isEmpty }
}

/// A theme that couldn't be used, and why, in words for Settings ▸ Extensions.
public struct ThemeProblem: Hashable, Sendable, CustomStringConvertible {
    /// The theme's name, or its id or position when it has none.
    public let theme: String
    public let reason: String

    public var description: String { "\(theme): \(reason)" }
}

/// One accent palette a plugin declares, in the design system's six roles per appearance.
public struct AccentContribution: Hashable, Sendable {
    public struct Swatch: Hashable, Sendable {
        public let accent: CodeColor
        public let hover: CodeColor
        public let pressed: CodeColor
        /// Accent-colored text on the background.
        public let text: CodeColor
        /// Text and glyphs on an accent fill.
        public let onAccent: CodeColor
        /// A faint wash of the accent.
        public let subtle: CodeColor
    }

    public let id: String
    public let name: String
    public let light: Swatch
    public let dark: Swatch
}

extension ThemeContributions {
    /// Text roles must reach these against the theme's background, as every built-in theme does:
    /// body text AA, syntax colors no fainter than the faintest built-in one (Rosé Pine Dawn's
    /// strings, 2.05:1). Upstream themes treat syntax color as a hint over the body text.
    public static let foregroundContrast = 4.5
    public static let syntaxContrast = 2.0
    /// Accent text on the background, and text on an accent fill.
    public static let accentContrast = 4.5

    static let syntaxRoles: [CodeTokenRole] = [
        .comment, .keyword, .string, .constant, .function, .variable, .tag, .type, .operator, .punctuation,
        .insertedForeground, .deletedForeground, .changedForeground,
    ]

    /// The code themes, checked: every role a readable color, at least one appearance, and text that
    /// reads on the theme's own background. Ids are prefixed with `namespace` (the plugin id) so they
    /// can't collide with built-in themes or other plugins'.
    public func codeThemes(namespace: String) -> [Result<CodeTheme, ThemeProblemError>] {
        code.enumerated().map { index, entry in
            Result { try Self.codeTheme(entry, namespace: namespace, position: index) }
                .mapError { $0 as? ThemeProblemError ?? ThemeProblemError(theme: "Code theme \(index + 1)", reason: "\($0)") }
        }
    }

    /// The accent palettes, checked: all six roles in both appearances, accent text readable on each
    /// background given, and text readable on the accent.
    public func accents(
        namespace: String, lightBackgrounds: [CodeColor], darkBackgrounds: [CodeColor]
    ) -> [Result<AccentContribution, ThemeProblemError>] {
        accents.enumerated().map { index, entry in
            Result {
                try Self.accent(
                    entry, namespace: namespace, position: index, lightBackgrounds: lightBackgrounds,
                    darkBackgrounds: darkBackgrounds)
            }
            .mapError { $0 as? ThemeProblemError ?? ThemeProblemError(theme: "Accent \(index + 1)", reason: "\($0)") }
        }
    }

    private static func codeTheme(_ entry: ThemeJSON, namespace: String, position: Int) throws -> CodeTheme {
        let (id, name) = try identity(of: entry, fallback: "Code theme \(position + 1)")
        let light = try entry["light"].map { try palette($0, theme: name, appearance: "light") }
        let dark = try entry["dark"].map { try palette($0, theme: name, appearance: "dark") }
        let themeID = CodeTheme.ID(rawValue: "\(namespace)/\(id)")
        switch (light, dark) {
        case (let light?, let dark?): return CodeTheme(id: themeID, name: name, light: light, dark: dark)
        case (let light?, nil): return CodeTheme(id: themeID, name: name, light: light)
        case (nil, let dark?): return CodeTheme(id: themeID, name: name, dark: dark)
        case (nil, nil): throw ThemeProblemError(theme: name, reason: "it has neither a \"light\" nor a \"dark\" palette")
        }
    }

    private static func palette(_ value: ThemeJSON, theme: String, appearance: String) throws -> CodePalette {
        var colors: [CodeTokenRole: CodeColor] = [:]
        for role in CodeTokenRole.allCases {
            guard let text = value[role.rawValue]?.string else {
                throw ThemeProblemError(theme: theme, reason: "its \(appearance) palette has no \"\(role.rawValue)\" color")
            }
            guard let color = CodeColor(hex: text) else {
                throw ThemeProblemError(theme: theme, reason: "\"\(text)\" isn't a color (\(appearance) \(role.rawValue)); use #RRGGBB or #RRGGBBAA")
            }
            colors[role] = color
        }
        let palette = CodePalette(colors, strong: try strongRoles(value["strong"], theme: theme, appearance: appearance))
        let background = palette.background
        if palette.foreground.contrastRatio(with: background) < foregroundContrast {
            throw ThemeProblemError(
                theme: theme, reason: "its \(appearance) text is too faint on its background (needs \(foregroundContrast):1)")
        }
        for role in syntaxRoles where palette[role].composited(over: background).contrastRatio(with: background) < syntaxContrast {
            throw ThemeProblemError(
                theme: theme,
                reason: "its \(appearance) \"\(role.rawValue)\" color is too faint on its background (needs \(syntaxContrast):1)")
        }
        return palette
    }

    private static func accent(
        _ entry: ThemeJSON, namespace: String, position: Int, lightBackgrounds: [CodeColor], darkBackgrounds: [CodeColor]
    ) throws -> AccentContribution {
        let (id, name) = try identity(of: entry, fallback: "Accent \(position + 1)")
        func swatch(_ appearance: String, backgrounds: [CodeColor]) throws -> AccentContribution.Swatch {
            guard let value = entry[appearance] else {
                throw ThemeProblemError(theme: name, reason: "it has no \"\(appearance)\" colors; accents need both")
            }
            func color(_ role: String) throws -> CodeColor {
                guard let text = value[role]?.string else {
                    throw ThemeProblemError(theme: name, reason: "its \(appearance) colors have no \"\(role)\"")
                }
                guard let color = CodeColor(hex: text), color.alpha == 0xFF else {
                    throw ThemeProblemError(theme: name, reason: "\"\(text)\" isn't an opaque color (\(appearance) \(role)); use #RRGGBB")
                }
                return color
            }
            let swatch = AccentContribution.Swatch(
                accent: try color("accent"), hover: try color("hover"), pressed: try color("pressed"),
                text: try color("text"), onAccent: try color("onAccent"), subtle: try color("subtle"))
            if swatch.onAccent.contrastRatio(with: swatch.accent) < accentContrast {
                throw ThemeProblemError(
                    theme: name, reason: "its \(appearance) \"onAccent\" is too faint on the accent (needs \(accentContrast):1)")
            }
            if backgrounds.contains(where: { swatch.text.contrastRatio(with: $0) < accentContrast }) {
                throw ThemeProblemError(
                    theme: name, reason: "its \(appearance) accent \"text\" is too faint on Native's background (needs \(accentContrast):1)")
            }
            return swatch
        }
        return AccentContribution(
            id: "\(namespace)/\(id)", name: name, light: try swatch("light", backgrounds: lightBackgrounds),
            dark: try swatch("dark", backgrounds: darkBackgrounds))
    }

    /// The optional `"strong"` list: role names set a heavier weight (`CodePalette.strong`).
    private static func strongRoles(_ value: ThemeJSON?, theme: String, appearance: String) throws -> Set<CodeTokenRole> {
        guard let value else { return [] }
        guard let items = value.array else {
            throw ThemeProblemError(theme: theme, reason: "its \(appearance) \"strong\" isn't a list of role names")
        }
        return Set(
            try items.map { item in
                guard let name = item.string, let role = CodeTokenRole(rawValue: name) else {
                    throw ThemeProblemError(
                        theme: theme,
                        reason: "its \(appearance) \"strong\" lists \(item.string.map { "\"\($0)\"" } ?? "a value") that isn't a role")
                }
                return role
            })
    }

    private static func identity(of entry: ThemeJSON, fallback: String) throws -> (id: String, name: String) {
        guard case .object = entry else { throw ThemeProblemError(theme: fallback, reason: "it isn't a JSON object") }
        let name = entry["name"]?.string ?? entry["id"]?.string ?? fallback
        guard let id = entry["id"]?.string, !id.isEmpty, !id.contains("/") else {
            throw ThemeProblemError(theme: name, reason: "it needs an \"id\" without slashes")
        }
        return (id, name)
    }
}

/// `ThemeProblem` as an error, for `Result`.
public struct ThemeProblemError: Error, Hashable, Sendable, CustomStringConvertible {
    public let problem: ThemeProblem

    init(theme: String, reason: String) {
        problem = ThemeProblem(theme: theme, reason: reason)
    }

    public var description: String { problem.description }
}

extension CodePalette {
    /// A palette from a complete role table.
    init(_ colors: [CodeTokenRole: CodeColor], strong: Set<CodeTokenRole> = []) {
        func color(_ role: CodeTokenRole) -> CodeColor { colors[role] ?? CodeColor(rgb: 0) }
        self.init(
            foreground: color(.foreground), background: color(.background), comment: color(.comment),
            keyword: color(.keyword), string: color(.string), constant: color(.constant), function: color(.function),
            variable: color(.variable), tag: color(.tag), type: color(.type), operator: color(.operator),
            regex: color(.regex), invalid: color(.invalid), punctuation: color(.punctuation),
            insertedForeground: color(.insertedForeground), insertedBackground: color(.insertedBackground),
            deletedForeground: color(.deletedForeground), deletedBackground: color(.deletedBackground),
            changedForeground: color(.changedForeground), changedBackground: color(.changedBackground),
            selection: color(.selection), lineHighlight: color(.lineHighlight), strong: strong)
    }
}

extension CodeColor {
    /// `#RRGGBB` or `#RRGGBBAA` (the `#` optional); nil for anything else.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(rgb: value)
        } else {
            self.init(rgb: value >> 8, alpha: UInt8(value & 0xFF))
        }
    }
}
