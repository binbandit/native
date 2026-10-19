import SwiftUI

/// Clean Up Merged's dimensions, from design system tokens.
nonisolated enum GitCleanupMetrics {
    static let sheetWidth: CGFloat = 560
    static let sheetHeight: CGFloat = 620
    /// Puts the 14pt checkbox's middle on the title's first baseline.
    static let glyphBaseline: CGFloat = 4
    static let disabledOpacity: CGFloat = 0.5
    /// Items indent under their group's checkbox.
    static let itemIndent: CGFloat = GitMetrics.checkbox + DS.Space.md
}
