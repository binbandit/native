import SwiftUI

/// Orca's status-bar metrics (`StatusBarSurface.tsx`, measured at 1x). Most map onto design-system
/// sizes; the few only the bar uses live here so items don't repeat them.
enum StatusBarMetrics {
    /// The bar, its top hairline included (Orca `h-6`).
    static let height = DS.Size.controlXS
    /// Between the window edge and the first segment (Orca `px-3`).
    static let edgeInset = DS.Space.lg
    /// Between segments (Orca `gap-3`).
    static let segmentSpacing = DS.Space.lg
    /// Around a segment's content, inside its hover wash (Orca `px-1 py-0.5`).
    static let segmentPadding = EdgeInsets(top: DS.Space.xxs, leading: DS.Space.xs, bottom: DS.Space.xxs, trailing: DS.Space.xs)
    /// Glyphs in segments: SF Symbols at this size match Lucide's `size-3` (12px).
    static let glyph: CGFloat = 10
    /// A task-status glyph in a segment; the dot-grid loader needs this much to read.
    static let statusGlyph = DS.Size.statusGlyph
    /// Detail panels (Orca's Resource Manager is `w-[26rem]`).
    static let panelWidth: CGFloat = 400
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
