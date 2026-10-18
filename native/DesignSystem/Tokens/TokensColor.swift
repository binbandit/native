import SwiftUI

// Color tokens. Every token is a dynamic `Color` that resolves per appearance, exposed on
// `ShapeStyle where Self == Color` so both `.foregroundStyle(.dsTextSecondary)` and
// `Color.dsTextSecondary` work.
//
// Sources:
// - Neutrals are oklab mixes of the foreground into the background (light: background #ffffff,
//   foreground #181818; dark: background #121212, foreground #ffffff), so every step keeps the same
//   hue. In dark mode the content is #171717, the sidebar edge #2c2c2c and the composer outline
//   #3e3e3e.
// - The sidebar is translucent (`.dsSidebarBackground()` or the system sidebar), so everything drawn
//   on it is either text or a translucent fill. `dsSidebarSolid` is only its backdrop when the user
//   turns transparency down (TokensTransparency.swift).
// - Light mode has two tones (TokensLightTone.swift): Paper, the values below, and Wool, a warm
//   off-white set that resolves against the environment's `dsLightTone` (`toned(_:wool:)`).
// - The accent follows the app-icon theme: it resolves against the environment's
//   `DSAccentPalette` (see AccentPalette.swift), `original` (graphite / off-white) by default.
// - `dsAttention` is the one status hue for "needs you" states, so they stand out under any accent.
// - Status hues are picked to read well as small glyphs on both appearances.

nonisolated extension ShapeStyle where Self == Color {
    // MARK: Layers

    /// The content pane behind the transcript.
    public static var dsBackground: Color { DSPalette.background }
    /// Fill of inputs, the composer and cards.
    public static var dsSurface: Color { DSPalette.surface }
    /// A step above the surface: hover cards, nested panels.
    public static var dsSurfaceRaised: Color { DSPalette.surfaceRaised }
    /// A step below: code blocks, wells, progress tracks.
    public static var dsSurfaceSunken: Color { DSPalette.surfaceSunken }
    /// Menus, popovers and tooltips.
    public static var dsOverlay: Color { DSPalette.overlay }
    /// The sidebar's backdrop when transparency is turned down; a step off the content pane, as the
    /// system sidebar material reads. Draw it only through `DSTransparency`, never as a row fill.
    public static var dsSidebarSolid: Color { DSPalette.sidebarSolid }

    // MARK: Translucent fills (they work on any layer, glass included)

    /// Hovered rows and ghost buttons: a faint wash, visible without competing with the selection.
    public static var dsHover: Color { DSPalette.hover }
    /// The selected row.
    public static var dsSelected: Color { DSPalette.selected }
    /// A control while the mouse is down.
    public static var dsPressed: Color { DSPalette.pressed }
    /// A quiet tint behind content set apart inline, such as inline code and the user's prompt in
    /// the transcript. Translucent, so it reads on any layer.
    public static var dsFill: Color { DSPalette.fill }

    // MARK: Borders

    /// Hairlines between regions: sidebar edge, card outlines, section rules.
    public static var dsSeparator: Color { DSPalette.separator }
    /// Outline of the composer and its pills.
    public static var dsBorder: Color { DSPalette.border }
    /// Outline of a hovered control.
    public static var dsBorderHover: Color { DSPalette.borderHover }
    /// Outline of secondary buttons.
    public static var dsBorderStrong: Color { DSPalette.borderStrong }
    /// Outline of keyboard hints and unlit level bars.
    public static var dsBorderInner: Color { DSPalette.borderInner }
    /// The track of a switch that's off: at least 3:1 against the background and the surface in
    /// every appearance and tone (WCAG's contrast for controls), so an off switch still reads as one.
    public static var dsSwitchOff: Color { DSPalette.switchOff }

    // MARK: Text

    public static var dsTextPrimary: Color { DSPalette.textPrimary }
    public static var dsTextSecondary: Color { DSPalette.textSecondary }
    public static var dsTextTertiary: Color { DSPalette.textTertiary }
    /// Disabled text and the faintest glyphs.
    public static var dsTextQuaternary: Color { DSPalette.textQuaternary }
    /// Text on a `dsTextPrimary` fill.
    public static var dsTextInverse: Color { DSPalette.textInverse }
    /// Text and glyphs on an accent fill (from the accent palette).
    public static var dsTextOnAccent: Color { Color(DSAccentStyle(role: .onAccent)) }

    // MARK: Accent (from the environment's `DSAccentPalette`)

    /// The update and send buttons, lit level bars, focused and active marks.
    public static var dsAccent: Color { Color(DSAccentStyle(role: .accent)) }
    public static var dsAccentHover: Color { Color(DSAccentStyle(role: .hover)) }
    public static var dsAccentPressed: Color { Color(DSAccentStyle(role: .pressed)) }
    /// Accent-colored text that clears AA on the background.
    public static var dsAccentText: Color { Color(DSAccentStyle(role: .text)) }
    /// A faint accent wash for selected or highlighted surfaces.
    public static var dsAccentSubtle: Color { Color(DSAccentStyle(role: .subtle)) }

    // MARK: Semantic

    /// Tasks waiting on the user: questions, approvals, plans to review. Amber, so it reads the
    /// same whatever the accent is.
    public static var dsAttention: Color { DSPalette.attention }

    public static var dsSuccess: Color { DSPalette.success }
    public static var dsWarning: Color { DSPalette.warning }
    public static var dsDanger: Color { DSPalette.danger }
    public static var dsInfo: Color { DSPalette.info }
    /// Merged pull requests and other "landed" states.
    public static var dsMerged: Color { DSPalette.merged }

    /// Fill of solid destructive buttons.
    public static var dsDangerFill: Color { DSPalette.dangerFill }
    public static var dsDangerFillHover: Color { DSPalette.dangerFillHover }
    public static var dsDangerFillPressed: Color { DSPalette.dangerFillPressed }

    // MARK: Charts

    /// Categorical series colors, always used in this order (first series `dsChart1`). Validated
    /// color-vision-safe (all pairs, protanopia and deuteranopia) on #FFFFFF and #171717.
    public static var dsChart1: Color { DSPalette.chart1 }
    public static var dsChart2: Color { DSPalette.chart2 }
    public static var dsChart3: Color { DSPalette.chart3 }

    /// Usage meters past 80%.
    public static var dsWarningFill: Color { DSPalette.warningFill }
    /// Usage meters at 100%.
    public static var dsDangerMeterFill: Color { DSPalette.dangerFill }
}

/// Backing storage for the tokens: each dynamic color is built once.
nonisolated private enum DSPalette {
    static let background = toned(dynamic("background", light: 0xFBFBFB, dark: 0x171717), wool: 0xF6F3EE)
    static let surface = toned(dynamic("surface", light: 0xFFFFFF, dark: 0x171717), wool: 0xFBF9F5)
    static let surfaceRaised = toned(dynamic("surfaceRaised", light: 0xF8F8F8, dark: 0x191919), wool: 0xF3F0EA)
    static let surfaceSunken = toned(dynamic("surfaceSunken", light: 0xF6F6F6, dark: 0x1D1D1D), wool: 0xF1EDE6)
    static let overlay = toned(dynamic("overlay", light: 0xFFFFFF, dark: 0x171717), wool: 0xFBF9F5)
    static let sidebarSolid = toned(dynamic("sidebarSolid", light: 0xF0F0F0, dark: 0x1F1F1F), wool: 0xEEEAE2)

    static let hover = toned(
        dynamic("hover", light: 0x000000, lightAlpha: 0.045, dark: 0xFFFFFF, darkAlpha: 0.06), wool: 0x3B2B14,
        woolAlpha: 0.045)
    static let selected = toned(
        dynamic("selected", light: 0x000000, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.1), wool: 0x3B2B14,
        woolAlpha: 0.08)
    static let pressed = toned(
        dynamic("pressed", light: 0x000000, lightAlpha: 0.11, dark: 0xFFFFFF, darkAlpha: 0.13), wool: 0x3B2B14,
        woolAlpha: 0.11)
    static let fill = toned(
        dynamic("fill", light: 0x000000, lightAlpha: 0.07, dark: 0xFFFFFF, darkAlpha: 0.07), wool: 0x3B2B14,
        woolAlpha: 0.07)

    static let separator = toned(dynamic("separator", light: 0xE8E8E8, dark: 0x2C2C2C), wool: 0xE6E1D8)
    // On glass, the same step from the surface as a translucent wash (`DSGlassAwareStyle`). Dark
    // glass renders a mid gray, where a faint white wash all but disappears, so dark's is stronger:
    // the composer's pills and outline keep 3:1 against the glass, active window or not (measured
    // #989897 on #4F4C4B active, 3.0:1; #949292 on #444241 inactive, 3.2:1).
    static let border = onGlass(
        toned(dynamic("border", light: 0xCBCBCB, dark: 0x3E3E3E), wool: 0xCDC7BC),
        glass: toned(
            dynamic("borderOnGlass", light: 0x000000, lightAlpha: 0.2, dark: 0xFFFFFF, darkAlpha: 0.38),
            wool: 0x3B2B14, woolAlpha: 0.245))
    static let borderHover = onGlass(
        toned(dynamic("borderHover", light: 0x949494, dark: 0x4F4F4F), wool: 0x979084),
        glass: toned(
            dynamic("borderHoverOnGlass", light: 0x000000, lightAlpha: 0.42, dark: 0xFFFFFF, darkAlpha: 0.55),
            wool: 0x3B2B14, woolAlpha: 0.51))
    static let borderStrong = toned(dynamic("borderStrong", light: 0x767676, dark: 0x616161), wool: 0x797266)
    static let borderInner = toned(dynamic("borderInner", light: 0xB2B2B2, dark: 0x2F2F2F), wool: 0xB4AEA3)
    // 3.3:1 on Paper's background, 3.4:1 on dark's, 3.5:1 on Wool's; the thumb (`surface`) keeps the
    // same contrast against it.
    static let switchOff = toned(dynamic("switchOff", light: 0x8A8A8A, dark: 0x6B6B6B), wool: 0x878177)

    static let textPrimary = dynamic("textPrimary", light: 0x181818, dark: 0xFFFFFF)
    static let textSecondary = toned(dynamic("textSecondary", light: 0x505050, dark: 0xAFAFAF), wool: 0x4B4B4B)
    static let textTertiary = toned(dynamic("textTertiary", light: 0x8D8D8D, dark: 0x717171), wool: 0x888888)
    static let textQuaternary = toned(dynamic("textQuaternary", light: 0xB2B2B2, dark: 0x4B4B4B), wool: 0xACACAC)
    static let textInverse = toned(dynamic("textInverse", light: 0xFFFFFF, dark: 0x121212), wool: 0xFBF9F5)

    static let attention = toned(dynamic("attention", light: 0xA35200, dark: 0xF59E3B), wool: 0x9C4E00)

    static let success = toned(dynamic("success", light: 0x16A249, dark: 0x4ADE80), wool: 0x159C46)
    static let warning = toned(dynamic("warning", light: 0x9A6700, dark: 0xD29922), wool: 0x936200)
    static let danger = toned(dynamic("danger", light: 0xDC2828, dark: 0xF87272), wool: 0xD32626)
    static let info = toned(dynamic("info", light: 0x2463EB, dark: 0x61A6FA), wool: 0x225FE1)
    static let merged = toned(dynamic("merged", light: 0x8250DF, dark: 0xA371F7), wool: 0x7C4CD6)

    static let dangerFill = dynamic("dangerFill", light: 0xD72D17, dark: 0xD72D17)
    static let dangerFillHover = dynamic("dangerFillHover", light: 0xA91F10, dark: 0xA91F10)
    static let dangerFillPressed = dynamic("dangerFillPressed", light: 0x741B12, dark: 0x741B12)
    static let warningFill = dynamic("warningFill", light: 0xEE9611, dark: 0xEE9611)
    static let chart1 = dynamic("chart1", light: 0x2A78D6, dark: 0x3987E5)
    static let chart2 = dynamic("chart2", light: 0xEB6834, dark: 0xD95926)
    static let chart3 = dynamic("chart3", light: 0x1BAF7A, dark: 0x199E70)

    /// `base` with its own value for Wool (TokensLightTone.swift). Wool's text and status values are
    /// a step darker than Paper's so each keeps Paper's contrast on Wool's background (#F6F3EE); its
    /// fills are a warm brown rather than black.
    static func toned(_ base: Color, wool: UInt32, woolAlpha: Float = 1) -> Color {
        Color(
            DSTonedStyle(
                base: base,
                wool: Color.Resolved(
                    red: Float((wool >> 16) & 0xFF) / 255,
                    green: Float((wool >> 8) & 0xFF) / 255,
                    blue: Float(wool & 0xFF) / 255,
                    opacity: woolAlpha
                )
            ))
    }

    /// `base`, with `glass` in its place on Liquid Glass.
    static func onGlass(_ base: Color, glass: Color) -> Color {
        Color(DSGlassAwareStyle(base: base, glass: glass))
    }

    /// An sRGB color that picks its light or dark value from the resolving appearance (high-contrast
    /// variants map to their base appearance).
    static func dynamic(
        _ name: String,
        light: UInt32,
        lightAlpha: CGFloat = 1,
        dark: UInt32,
        darkAlpha: CGFloat = 1
    ) -> Color {
        Color(
            DSPlatformColor.dsDynamic(
                name: name,
                light: .dsSRGB(light, alpha: lightAlpha),
                dark: .dsSRGB(dark, alpha: darkAlpha)
            ))
    }
}
