import SwiftUI

/// The accent colors for one app-icon theme. Native's accent follows the icon the user picked, so
/// `.dsAccent` and its relatives read the palette from the environment:
///
///     WindowContent().dsAccentPalette(themeID: iconPreferences.theme.rawValue)
///
/// Hues are sampled from the theme icons (`design/app-icon/themes/AppIcon-<theme>-*.png`): in
/// light mode the accent is the icon's deep emblem color under white text, in dark mode a lighter
/// tone of the same hue under dark text, like the light emblem on the dark tile. Every pair is
/// contrast-checked (text on accent and accent text on the background both at least 4.5:1).
/// `original` is monochrome, graphite or off-white, leaving color to statuses.
public nonisolated struct DSAccentPalette: Hashable, Identifiable, Sendable {
    /// The icon theme's id, e.g. "cobalt".
    public let id: String
    /// A display name, e.g. "Cobalt".
    public let name: String
    let light: Swatch
    let dark: Swatch

    /// One appearance's colors, as 0xRRGGBB.
    struct Swatch: Hashable, Sendable {
        let accent: UInt32
        let hover: UInt32
        let pressed: UInt32
        /// Accent-colored text on the background.
        let text: UInt32
        /// Text and glyphs on an accent fill.
        let onAccent: UInt32
        /// A faint wash of the accent for selected or highlighted surfaces.
        let subtle: UInt32
    }

    func swatch(for colorScheme: ColorScheme) -> Swatch {
        colorScheme == .dark ? dark : light
    }

    /// The palette for an icon theme id; unknown ids get `original`.
    public static func named(_ id: String) -> DSAccentPalette {
        all.first { $0.id == id } ?? .original
    }

    public static let all: [DSAccentPalette] = [.original, .cobalt, .fern, .ember, .prism, .arcade, .glass, .nightly]

    public static let original = DSAccentPalette(
        id: "original", name: "Original",
        light: Swatch(accent: 0x202226, hover: 0x35383E, pressed: 0x111214, text: 0x202226, onAccent: 0xFFFFFF, subtle: 0xE8E9EA),
        dark: Swatch(accent: 0xECEDEF, hover: 0xFFFFFF, pressed: 0xC1C2C4, text: 0xECEDEF, onAccent: 0x121316, subtle: 0x2E2F31)
    )
    public static let cobalt = DSAccentPalette(
        id: "cobalt", name: "Cobalt",
        light: Swatch(accent: 0x2C5BA9, hover: 0x22498A, pressed: 0x18386B, text: 0x2C5BA9, onAccent: 0xFFFFFF, subtle: 0xEBF0F8),
        dark: Swatch(accent: 0x8EB2FF, hover: 0xA0BFFF, pressed: 0x7391D1, text: 0x8EB2FF, onAccent: 0x0B1835, subtle: 0x1F2A3F)
    )
    public static let fern = DSAccentPalette(
        id: "fern", name: "Fern",
        light: Swatch(accent: 0x2F6B50, hover: 0x255640, pressed: 0x1A4230, text: 0x2F6B50, onAccent: 0xFFFFFF, subtle: 0xECF1EE),
        dark: Swatch(accent: 0x8FD0AE, hover: 0xA2D8BB, pressed: 0x74AA8E, text: 0x8FD0AE, onAccent: 0x0C2219, subtle: 0x1F2E27)
    )
    public static let ember = DSAccentPalette(
        id: "ember", name: "Ember",
        light: Swatch(accent: 0xA24A3C, hover: 0x843B2F, pressed: 0x672C23, text: 0xA24A3C, onAccent: 0xFFFFFF, subtle: 0xF8EEEC),
        dark: Swatch(accent: 0xF4B39C, hover: 0xF7BFAC, pressed: 0xC8927F, text: 0xF4B39C, onAccent: 0x2A120D, subtle: 0x332623)
    )
    public static let prism = DSAccentPalette(
        id: "prism", name: "Prism",
        light: Swatch(accent: 0x7A3CE0, hover: 0x632FB7, pressed: 0x4C2390, text: 0x7A3CE0, onAccent: 0xFFFFFF, subtle: 0xF1EFFE),
        dark: Swatch(accent: 0xC69CFF, hover: 0xCFACFF, pressed: 0xA27FD1, text: 0xC69CFF, onAccent: 0x1E0B3D, subtle: 0x2A2338)
    )
    public static let arcade = DSAccentPalette(
        id: "arcade", name: "Arcade",
        light: Swatch(accent: 0xC42E7E, hover: 0xA02466, pressed: 0x7D1A4F, text: 0xC42E7E, onAccent: 0xFFFFFF, subtle: 0xFCEDF3),
        dark: Swatch(accent: 0xC9EC4F, hover: 0xD1F075, pressed: 0xA4C13F, text: 0xC9EC4F, onAccent: 0x1B2203, subtle: 0x2A3020)
    )
    public static let glass = DSAccentPalette(
        id: "glass", name: "Glass",
        light: Swatch(accent: 0x3E6E8C, hover: 0x315972, pressed: 0x244458, text: 0x3E6E8C, onAccent: 0xFFFFFF, subtle: 0xEDF1F4),
        dark: Swatch(accent: 0x9CC4DC, hover: 0xACCDE2, pressed: 0x7FA0B4, text: 0x9CC4DC, onAccent: 0x0A2433, subtle: 0x222C32)
    )
    public static let nightly = DSAccentPalette(
        id: "nightly", name: "Nightly",
        light: Swatch(accent: 0x4F4A9A, hover: 0x3F3B7D, pressed: 0x302C61, text: 0x4F4A9A, onAccent: 0xFFFFFF, subtle: 0xEDEEF6),
        dark: Swatch(accent: 0xAFB4FF, hover: 0xBBC0FF, pressed: 0x8F93D1, text: 0xAFB4FF, onAccent: 0x10123A, subtle: 0x25263A)
    )
}

nonisolated extension EnvironmentValues {
    /// The accent palette `.dsAccent` and its relatives resolve against.
    @Entry public var dsAccentPalette: DSAccentPalette = .original
}

extension View {
    /// Sets the accent palette for this view and its children, and tints system controls to match.
    public func dsAccentPalette(_ palette: DSAccentPalette) -> some View {
        tint(.dsAccent)
            .environment(\.dsAccentPalette, palette)
    }

    /// Sets the accent palette for an icon theme id (unknown ids get `original`).
    public func dsAccentPalette(themeID: String) -> some View {
        dsAccentPalette(.named(themeID))
    }
}

/// A color that resolves to one role of the environment's accent palette.
nonisolated struct DSAccentStyle: ShapeStyle, Hashable {
    enum Role: Hashable {
        case accent, hover, pressed, text, onAccent, subtle
    }

    let role: Role

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let swatch = environment.dsAccentPalette.swatch(for: environment.colorScheme)
        let hex = switch role {
        case .accent: swatch.accent
        case .hover: swatch.hover
        case .pressed: swatch.pressed
        case .text: swatch.text
        case .onAccent: swatch.onAccent
        case .subtle: swatch.subtle
        }
        return Color.Resolved(
            red: Float((hex >> 16) & 0xFF) / 255,
            green: Float((hex >> 8) & 0xFF) / 255,
            blue: Float(hex & 0xFF) / 255
        )
    }
}
