import SwiftUI

/// The few sizes only Bubbles uses, kept here so its views don't repeat them. Everything else comes
/// from the design system.
nonisolated enum BubbleMetrics {
    /// A bubble's corners, and the tighter corners where bubbles of one group meet.
    static let radius: CGFloat = 18
    static let groupedRadius: CGFloat = 6
    /// How far the tail reaches past the bubble. Every bubble reserves it, so edges line up.
    static let tailWidth: CGFloat = 6
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
/// follow the app icon theme), the agent's a neutral wash of the text color.
nonisolated enum BubblePalette {
    static let outgoing = Color.dsAccent
    static let outgoingText = Color.dsTextOnAccent
    static let incoming = Color.dsTextPrimary.opacity(0.07)
    static let tray = Color.dsSurfaceSunken
    static let trayBorder = Color.dsSeparator
}
