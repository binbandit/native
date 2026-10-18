import SwiftUI

/// Sizes only the status bar's items and panels use. The bar's own height, spacing and glyphs come
/// from the design system (`StatusBarSurface`, `DS.StatusBar`); panels are `PopoverPanel`s.
enum StatusBarMetrics {
    /// A task-status glyph in a segment; the dot-grid loader needs this much to read.
    static let statusGlyph = DS.Size.statusGlyph
    /// Disclosure chevrons in panel rows.
    static let glyph: CGFloat = 10
    /// The tallest a panel's list grows before it scrolls.
    static let panelListHeight: CGFloat = 320
    /// Sparklines: in segments' panels, beside a group's numbers.
    static let sparklineSize = CGSize(width: 56, height: 14)
    /// The table's numeric columns.
    static let cpuColumn: CGFloat = 56
    static let memoryColumn: CGFloat = 76
    /// Process rows indent this much per level below their group's root.
    static let indent = DS.Space.md
}
