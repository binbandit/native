import SwiftUI

/// Settings' metrics. Most map onto design-system sizes; the rest are the few layout
/// values only this window uses, kept here so pages don't repeat them.
enum SettingsMetrics {
    /// The nav column, 256pt.
    static let navWidth = DS.Size.sidebarWidth
    /// Page content: inset 40pt (`px-10`), 24pt below the toolbar, at most 896pt wide.
    static let pageInset: CGFloat = 40
    static let pageTopInset = DS.Space.xxl
    static let pageBottomInset: CGFloat = 88
    static let pageMaxWidth: CGFloat = 896
    /// Between rows, either side of their hairline (`space-y-5` and `pt-5`).
    static let rowSpacing: CGFloat = 20
    /// Between a row's text and its control (`gap-8`).
    static let rowControlSpacing = DS.Space.xxxl
    /// A row title's line (`min-h-7`).
    static let rowTitleHeight = DS.Size.controlSM
    static let controlHeight = DS.Size.controlMD
    static let selectWidth: CGFloat = 140
    static let switchSize = CGSize(width: 40, height: 20)
    static let switchThumb: CGFloat = 16
    static let iconTile: CGFloat = 40
    /// A glyph in a settings button, a size below its 14pt title.
    static let buttonGlyph: CGFloat = 13
    /// Above a section heading, on top of the page's own spacing, so sections read apart from rows.
    static let sectionTopInset = DS.Space.xl
    /// Badges beside a row title (`h-5`).
    static let badgeHeight: CGFloat = 20
    /// Nav rows: 32pt tall, 4pt apart, groups 20pt apart, 16pt icons 12pt before the label.
    static let navItemSpacing = DS.Space.xs
    static let navGroupSpacing: CGFloat = 20
    static let navIcon: CGFloat = 16
    /// SF Symbol point sizes that match thin 1pt-stroke glyphs at the nav's and tiles' icon sizes.
    static let navGlyph: CGFloat = 14
    static let tileGlyph: CGFloat = 17
    static let searchGlyph: CGFloat = 12
    static let chevronGlyph: CGFloat = 9
    static let returnGlyph: CGFloat = 11
    /// The ⌘F hint in the search field and its 10pt glyphs.
    static let hintHeight: CGFloat = 16
    static let hintFontSize: CGFloat = 10
    /// The search results popup: 6pt below the field, at most 480pt tall, 30 results.
    static let resultsOffset = DS.Space.sm
    static let resultsMaxHeight: CGFloat = 480
    static let resultsLimit = 30
    /// The reveal ring: 2pt wide, 8pt outside the row.
    static let revealRingWidth: CGFloat = 2
    static let revealRingOutset: CGFloat = 10
}

/// Settings' text styles in the design system's fonts, with CSS-style line heights: the
/// leading a line box adds beyond the font's own height goes half above and half below, and
/// between wrapped lines.
struct SettingsTextStyle {
    let font: Font
    let tracking: CGFloat
    let leading: CGFloat

    private init(
        _ font: Font, size: CGFloat, weight: DSTypography.Weight = .regular, design: DSTypography.Design = .sans,
        lineHeight: CGFloat, trackingEm: CGFloat = 0
    ) {
        let metrics = DSTypography.platformFont(size: size, weight: weight, design: design)
        self.font = font
        tracking = trackingEm * size
        leading = max(0, lineHeight - (metrics.ascender - metrics.descender + metrics.leading))
    }

    /// `text-xs`: details and nav group labels.
    static let caption = SettingsTextStyle(.dsBody, size: 12, lineHeight: 16, trackingEm: 0.01)
    /// `text-sm`: descriptions, nav items and control values.
    static let body = SettingsTextStyle(.ds(14), size: 14, lineHeight: 20)
    /// `text-sm font-medium`: row titles.
    static let bodyMedium = SettingsTextStyle(.dsHeadline, size: 14, weight: .medium, lineHeight: 20)
    /// `text-base font-medium`: section headings, a step above row titles.
    static let heading = SettingsTextStyle(.dsTitle3, size: 16, weight: .medium, lineHeight: 24)
    /// `text-2xl`: page titles, in Geist at 300, light enough that the title sits back from the
    /// rows under it.
    static let title = SettingsTextStyle(
        .ds(24, weight: .light), size: 24, weight: .light, lineHeight: 32, trackingEm: -0.024)
    /// `font-mono text-xs`: commands and paths.
    static let mono = SettingsTextStyle(.dsMono, size: 12, design: .mono, lineHeight: 16)
}

extension View {
    func settingsText(_ style: SettingsTextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.leading)
            .padding(.vertical, style.leading / 2)
    }
}

extension View {
    /// The shape macOS draws a control's keyboard focus ring in. iPadOS draws its own.
    @ViewBuilder
    func settingsFocusShape(_ shape: some Shape) -> some View {
        #if os(macOS)
        contentShape(.focusEffect, shape)
        #else
        self
        #endif
    }
}
