import SwiftUI

/// Sizes particular to the usage views, derived from the design system's scale.
enum UsageMetrics {
    /// The breakdown popover: room for a tool name and its count on one line.
    static let breakdownWidth: CGFloat = DS.Size.sidebarWidth + DS.Space.xxxl * 3
    /// The breakdown's scrolling part, so a long tool list doesn't run off the screen.
    static let breakdownMaxHeight: CGFloat = DS.Size.sidebarWidth * 2
    static let barHeight: CGFloat = DS.Space.md + DS.Space.xxs
    /// The ring in a task row and in the composer.
    static let ringSize: CGFloat = DS.Size.navIcon
    /// The swatch beside a category in the breakdown's table.
    static let swatchSize: CGFloat = DS.Space.md
    /// The share column of the category table.
    static let shareColumnWidth: CGFloat = DS.Space.xxxl + DS.Space.lg
    /// The activity graph's metric picker: "Agent time" and its chevron.
    static let metricSelectWidth: CGFloat = DS.Size.sidebarWidth / 2
}
