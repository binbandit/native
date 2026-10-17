import SwiftUI

/// The home page's metrics. The composition follows the reference app's home (`HomeContent` and
/// `QuickActions`), so the shared measurements note the Tailwind class they stand for.
nonisolated enum HomeLayout {
    // MARK: Column and cards

    /// The cards' column (`max-w-[640px]`), which the recent tasks share so everything lines up.
    static let columnWidth: CGFloat = 640
    /// Cards per row (`md:grid-cols-3`).
    static let maxColumns = 3
    /// Below this a card's label stops fitting, so rows get fewer cards.
    static let minCardWidth: CGFloat = 150
    /// `h-32`.
    static let cardHeight: CGFloat = 128
    /// `gap-3`.
    static let cardSpacing = DS.Space.lg
    /// `p-4`.
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

    /// Under the hero (`mb-12`).
    static let heroSpacingBelow: CGFloat = 48
    /// the reference app nudges the cards down once there's work (`mt-4`); here, once there are tasks.
    static let activitySpacing = DS.Space.xl
    /// Above the footer link (`mt-6`).
    static let footerSpacing = DS.Space.xxl
    /// Above the recent tasks.
    static let sectionSpacing: CGFloat = 40
    /// The hero's distance from the top of the window (`mt-56`), kept while the content fits.
    static let heroTop: CGFloat = 224
    /// Page gutters (`px-8`).
    static let gutter = DS.Space.xxxl

    // MARK: Lists

    /// How many recent tasks the page lists; the sidebar has the rest.
    static let recentTaskLimit = 5
    /// The trailing label of task rows: the project or agent.
    static let taskDetailWidth: CGFloat = 120
    /// The age column of task rows (`w-12`).
    static let ageColumnWidth: CGFloat = 48

    // MARK: Motion

    /// The cards fading in under the hero (`animate-in fade-in duration-1000`).
    static let contentFadeIn = Animation.easeOut(duration: 1).delay(0.15)
}
