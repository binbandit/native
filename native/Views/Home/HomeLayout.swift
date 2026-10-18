import SwiftUI

/// The home page's metrics.
nonisolated enum HomeLayout {
    // MARK: Column and cards

    /// The cards' column, which the recent tasks share so everything lines up.
    static let columnWidth: CGFloat = 640
    /// Cards per row.
    static let maxColumns = 3
    /// Below this a card's label stops fitting, so rows get fewer cards.
    static let minCardWidth: CGFloat = 176
    static let cardHeight: CGFloat = 128
    static let cardSpacing = DS.Space.lg
    /// A card's height as a row, when only one fits across.
    static let compactCardHeight: CGFloat = 60
    static let cardPadding = DS.Space.xl
    /// A card's glyph: 14pt in a 16pt slot matches the weight of 16pt line icons.
    static let cardGlyph = Font.system(size: 14, weight: .regular)
    static let cardGlyphSlot = DS.Size.rowLeading

    // MARK: Hero

    /// The lockup's wordmark size; its emblem is twice as tall.
    static let heroSize: CGFloat = 28
    static let heroEntrance = Animation.smooth(duration: 0.9)
    static let heroEntranceScale: CGFloat = 0.96
    static let heroEntranceOffset: CGFloat = 6

    // MARK: Vertical rhythm

    /// Under the hero.
    static let heroSpacingBelow: CGFloat = 48
    /// Nudges the cards down once there are tasks, so the work reads as its own band.
    static let activitySpacing = DS.Space.xl
    /// Above the footer link.
    static let footerSpacing = DS.Space.xxl
    /// Above the recent tasks.
    static let sectionSpacing: CGFloat = 40
    /// The hero's distance from the top of the window, kept while the content fits.
    static let heroTop: CGFloat = 224
    /// Page gutters, and the tighter ones of a narrow column.
    static let gutter = DS.Space.xxxl
    static let compactGutter = DS.Space.xl
    /// Below this page width the gutters tighten and task rows drop their trailing label.
    static let compactWidth: CGFloat = 520

    // MARK: Lists

    /// The Needs You strip's outline, strong enough to read as urgent without shouting.
    static let attentionOutlineOpacity = 0.45

    /// How many recent tasks the page lists; the sidebar has the rest.
    static let recentTaskLimit = 5
    /// The trailing label of task rows: the project or agent.
    static let taskDetailWidth: CGFloat = 120
    /// The age column of task rows.
    static let ageColumnWidth: CGFloat = 48

    // MARK: Motion

    /// The cards fading in under the hero.
    static let contentFadeIn = Animation.easeOut(duration: 1).delay(0.15)
}
