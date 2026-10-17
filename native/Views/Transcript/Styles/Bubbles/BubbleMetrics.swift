import SwiftUI

/// The few sizes only Bubbles uses, kept here so its views don't repeat them. Everything else comes
/// from the design system.
nonisolated enum BubbleMetrics {
    /// A bubble's corners, and the tighter corners where bubbles of one group meet.
    static let radius: CGFloat = 18
    static let groupedRadius: CGFloat = 6
    /// How far the tail reaches past the bubble, and how far up the side it starts. Every bubble
    /// reserves the width, so edges line up.
    static let tailWidth: CGFloat = 7
    static let tailHeight: CGFloat = 14
    static let horizontalPadding = DS.Space.lg
    static let verticalPadding = DS.Space.md

    /// The share of the column a bubble may take: the agent's replies get more room for code.
    static let userFraction: CGFloat = 0.75
    static let agentFraction: CGFloat = 0.86

    static let groupSpacing = DS.Space.xxs
    static let rowSpacing = DS.Space.lg
    static let speakerSpacing = DS.Space.xl

    static let trayRadius: CGFloat = 14
    static let trayHorizontalPadding = DS.Space.lg
    static let trayVerticalPadding = DS.Space.xs
    static let trayRowSpacing = DS.Space.xxs

    static let timestampSpacing = DS.Space.md
    static let typingDots: CGFloat = 16
}

/// Bubbles' colors, all from design-system tokens: the user's bubbles take the accent (so they
/// follow the app icon theme), the agent's a neutral wash of the text color. A monochrome accent
/// (Original) would make the user's bubbles glaring slabs of near-black or near-white, so there
/// they take a stronger wash than the agent's instead.
nonisolated enum BubblePalette {
    static let incoming = Color.dsTextPrimary.opacity(0.07)

    static func outgoing(_ palette: DSAccentPalette) -> Color {
        palette.isMonochrome ? .dsTextPrimary.opacity(0.13) : .dsAccent
    }

    static func outgoingText(_ palette: DSAccentPalette) -> Color {
        palette.isMonochrome ? .dsTextPrimary : .dsTextOnAccent
    }

    static let tray = Color.dsSurfaceSunken
    static let trayBorder = Color.dsSeparator
}
