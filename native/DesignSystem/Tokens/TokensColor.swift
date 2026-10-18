import SwiftUI

// Color tokens. Every token is a dynamic `Color` that resolves per appearance, exposed on
// `ShapeStyle where Self == Color` so both `.foregroundStyle(.dsTextSecondary)` and
// `Color.dsTextSecondary` work.
//
// Sources:
// - Neutrals come from the reference app's default "the reference app" appearance preset (light: background #ffffff,
//   foreground #181818; dark: background #121212, foreground #ffffff), whose core-ui v2 tokens are
//   oklab mixes of foreground into background (`PALETTE_TOKEN_MIXES`, contrast 50). Dark values were
//   checked against screenshots of the reference app: content #171717, sidebar edge #2c2c2c, composer outline
//   #3e3e3e.
// - The sidebar is translucent (`.dsSidebarBackground()` or the system sidebar), so everything drawn
//   on it is either text or a translucent fill. `dsSidebarSolid` is only its backdrop when the user
//   turns transparency down (TokensTransparency.swift).
// - The accent follows the app-icon theme: it resolves against the environment's
//   `DSAccentPalette` (see AccentPalette.swift), `original` (graphite / off-white) by default.
// - `dsAttention` is the one status hue for "needs you" states, so they stand out under any accent.
// - Status hues are the reference app's (`--git-green`, `--destructive`, `--checks-pending`,
//   `--sidebar-blue`), which read well as small glyphs on both appearances.

nonisolated extension ShapeStyle where Self == Color {
    // MARK: Layers

    /// The content pane behind the transcript (the reference app `bg/surface`).
    public static var dsBackground: Color { DSPalette.background }
    /// Fill of inputs, the composer and cards (the reference app `input/bg`).
    public static var dsSurface: Color { DSPalette.surface }
    /// A step above the surface: hover cards, nested panels (the reference app `bg/surface-raised`).
    public static var dsSurfaceRaised: Color { DSPalette.surfaceRaised }
    /// A step below: code blocks, wells, progress tracks (the reference app `code/bg`).
    public static var dsSurfaceSunken: Color { DSPalette.surfaceSunken }
    /// Menus, popovers and tooltips (the reference app `bg/overlay`).
    public static var dsOverlay: Color { DSPalette.overlay }
    /// The sidebar's backdrop when transparency is turned down; a step off the content pane, as the
    /// system sidebar material reads. Draw it only through `DSTransparency`, never as a row fill.
    public static var dsSidebarSolid: Color { DSPalette.sidebarSolid }

    // MARK: Interaction fills (translucent, so they work on any layer, glass included)

    /// Hovered rows and ghost buttons (measured: the reference app's hovered row is ~7% white over its
    /// sidebar, the reference app's hover a 6% mix).
    public static var dsHover: Color { DSPalette.hover }
    /// The selected row.
    public static var dsSelected: Color { DSPalette.selected }
    /// A control while the mouse is down.
    public static var dsPressed: Color { DSPalette.pressed }

    // MARK: Borders

    /// Hairlines between regions: sidebar edge, card outlines, section rules (the reference app `border/outer`).
    public static var dsSeparator: Color { DSPalette.separator }
    /// Outline of the composer and its pills (the reference app `input/border/default`).
    public static var dsBorder: Color { DSPalette.border }
    /// Outline of a hovered control (the reference app `input/border/hover`).
    public static var dsBorderHover: Color { DSPalette.borderHover }
    /// Outline of secondary buttons (the reference app `button/secondary/border/default`).
    public static var dsBorderStrong: Color { DSPalette.borderStrong }
    /// Outline of keyboard hints and unlit level bars (the reference app `border/inner`).
    public static var dsBorderInner: Color { DSPalette.borderInner }

    // MARK: Text

    public static var dsTextPrimary: Color { DSPalette.textPrimary }
    public static var dsTextSecondary: Color { DSPalette.textSecondary }
    public static var dsTextTertiary: Color { DSPalette.textTertiary }
    /// Disabled text and the faintest glyphs (the reference app `text/disabled`).
    public static var dsTextQuaternary: Color { DSPalette.textQuaternary }
    /// Text on a `dsTextPrimary` fill (the reference app `text/inverse`).
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

    /// Fill of solid destructive buttons (the reference app `button/destructive/bg`).
    public static var dsDangerFill: Color { DSPalette.dangerFill }
    public static var dsDangerFillHover: Color { DSPalette.dangerFillHover }
    public static var dsDangerFillPressed: Color { DSPalette.dangerFillPressed }

    // MARK: Charts

    /// Categorical series colors, always used in this order (first series `dsChart1`). Validated
    /// color-vision-safe (all pairs, protanopia and deuteranopia) on #FFFFFF and #171717.
    public static var dsChart1: Color { DSPalette.chart1 }
    public static var dsChart2: Color { DSPalette.chart2 }
    public static var dsChart3: Color { DSPalette.chart3 }

    /// Usage meters past 80% (the reference app `warning/fill`).
    public static var dsWarningFill: Color { DSPalette.warningFill }
    /// Usage meters at 100% (the reference app `error/fill`).
    public static var dsDangerMeterFill: Color { DSPalette.dangerFill }
}

/// Backing storage for the tokens: each dynamic color is built once.
nonisolated private enum DSPalette {
    static let background = dynamic("background", light: 0xFBFBFB, dark: 0x171717)
    static let surface = dynamic("surface", light: 0xFFFFFF, dark: 0x171717)
    static let surfaceRaised = dynamic("surfaceRaised", light: 0xF8F8F8, dark: 0x191919)
    static let surfaceSunken = dynamic("surfaceSunken", light: 0xF6F6F6, dark: 0x1D1D1D)
    static let overlay = dynamic("overlay", light: 0xFFFFFF, dark: 0x171717)
    static let sidebarSolid = dynamic("sidebarSolid", light: 0xF0F0F0, dark: 0x1F1F1F)

    static let hover = dynamic("hover", light: 0x000000, lightAlpha: 0.045, dark: 0xFFFFFF, darkAlpha: 0.06)
    static let selected = dynamic("selected", light: 0x000000, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.1)
    static let pressed = dynamic("pressed", light: 0x000000, lightAlpha: 0.11, dark: 0xFFFFFF, darkAlpha: 0.13)

    static let separator = dynamic("separator", light: 0xE8E8E8, dark: 0x2C2C2C)
    static let border = dynamic("border", light: 0xCBCBCB, dark: 0x3E3E3E)
    static let borderHover = dynamic("borderHover", light: 0x949494, dark: 0x4F4F4F)
    static let borderStrong = dynamic("borderStrong", light: 0x767676, dark: 0x616161)
    static let borderInner = dynamic("borderInner", light: 0xB2B2B2, dark: 0x2F2F2F)

    static let textPrimary = dynamic("textPrimary", light: 0x181818, dark: 0xFFFFFF)
    static let textSecondary = dynamic("textSecondary", light: 0x505050, dark: 0xAFAFAF)
    static let textTertiary = dynamic("textTertiary", light: 0x8D8D8D, dark: 0x717171)
    static let textQuaternary = dynamic("textQuaternary", light: 0xB2B2B2, dark: 0x4B4B4B)
    static let textInverse = dynamic("textInverse", light: 0xFFFFFF, dark: 0x121212)

    static let attention = dynamic("attention", light: 0xA35200, dark: 0xF59E3B)

    static let success = dynamic("success", light: 0x16A249, dark: 0x4ADE80)
    static let warning = dynamic("warning", light: 0x9A6700, dark: 0xD29922)
    static let danger = dynamic("danger", light: 0xDC2828, dark: 0xF87272)
    static let info = dynamic("info", light: 0x2463EB, dark: 0x61A6FA)
    static let merged = dynamic("merged", light: 0x8250DF, dark: 0xA371F7)

    static let dangerFill = dynamic("dangerFill", light: 0xD72D17, dark: 0xD72D17)
    static let dangerFillHover = dynamic("dangerFillHover", light: 0xA91F10, dark: 0xA91F10)
    static let dangerFillPressed = dynamic("dangerFillPressed", light: 0x741B12, dark: 0x741B12)
    static let warningFill = dynamic("warningFill", light: 0xEE9611, dark: 0xEE9611)
    static let chart1 = dynamic("chart1", light: 0x2A78D6, dark: 0x3987E5)
    static let chart2 = dynamic("chart2", light: 0xEB6834, dark: 0xD95926)
    static let chart3 = dynamic("chart3", light: 0x1BAF7A, dark: 0x199E70)

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
