import SwiftUI

/// The new-session state's layout metrics, on top of the design system's.
nonisolated enum NewSessionMetrics {
    /// The project's name shrinks this far in a narrow window before it truncates.
    static let titleMinimumScale: CGFloat = 0.55
    /// The project's own icon, before its name: about the display type's cap height.
    static let titleIcon: CGFloat = 28
    /// The interlock mark between a task's base branch and its own: the line's cap height.
    static let linkMarkHeight: CGFloat = 9
    /// A starting point's row, generous enough to aim at.
    static let ledgerRow: CGFloat = 44
    /// The verb column, so every row's object starts at the same edge.
    static let verbColumn: CGFloat = 88
}
