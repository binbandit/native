import SwiftUI

/// The new-session empty states' metrics, on top of the design system's.
nonisolated enum NewSessionMetrics {
    // MARK: Quiet focus

    /// The project's name, set large: the one big thing on the screen.
    static let titleSize: CGFloat = 40
    /// Tight, as display type wants (-0.025em).
    static let titleTracking: CGFloat = -1
    /// The name shrinks this far in a narrow window before it truncates.
    static let titleMinimumScale: CGFloat = 0.55
    /// The project's own icon, before the name.
    static let titleIcon: CGFloat = 28

    // MARK: Shared

    /// Between the empty state and the composer under it, so the two read as one block.
    static let composerGap: CGFloat = 32
    /// The interlock mark between a task's base branch and its own, at the line's cap height.
    static let linkMarkHeight: CGFloat = 9
    /// Below this column width, lines stack and trailing details drop.
    static let compactWidth: CGFloat = 480

    // MARK: Workbench

    /// The project's icon in the header.
    static let headerIcon: CGFloat = 20
    /// Rows in the lists.
    static let listRow: CGFloat = 30
    /// What leads a row, a pull request's number or a task's age, so titles line up.
    static let numberColumn: CGFloat = 40
    /// The trailing detail (agent, branch) of a row.
    static let detailColumn: CGFloat = 132
    /// How many of each list show; the sidebar and the Pull Requests page have the rest.
    static let listLimit = 3

    // MARK: Starting points

    /// A starting point's row: a two-line target, generous enough to aim at.
    static let ledgerRow: CGFloat = 44
    /// The verb column, so every object starts at the same edge.
    static let verbColumn: CGFloat = 88
    /// How many starting points show at most.
    static let ledgerLimit = 5
}
