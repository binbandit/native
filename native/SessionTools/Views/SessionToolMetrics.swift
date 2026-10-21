import CoreGraphics

/// The session tools' layout sizes, in one place; everything visual comes from the design system.
nonisolated enum SessionToolMetrics {
    /// The side panel's widths: the floor fits a diff's file list, the ideal a readable diff.
    static let sidePanelMinWidth: CGFloat = 340
    static let sidePanelIdealWidth: CGFloat = 420
    static let sidePanelMaxWidth: CGFloat = 720
}
