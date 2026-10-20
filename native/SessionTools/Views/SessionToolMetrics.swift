import CoreGraphics

/// The session tools' layout sizes, in one place; everything visual comes from the design system.
nonisolated enum SessionToolMetrics {
    /// The side panel's widths: the floor fits a diff's file list, the ideal a readable diff.
    static let sidePanelMinWidth: CGFloat = 340
    static let sidePanelIdealWidth: CGFloat = 420
    static let sidePanelMaxWidth: CGFloat = 720
    /// The narrowest the conversation gets beside the side panel. Narrower, and a side tool opens over
    /// the conversation instead: at 440pt the conversation wrapped most lines of a reply and the
    /// composer's pills.
    static let conversationBesidePanelMinWidth: CGFloat = 520
    /// A place's tab strip, and a shade's header.
    static let stripHeight: CGFloat = DS.Size.controlMD + DS.Space.xs
    /// The workbench's pane: where it starts, and the least it shrinks to.
    static let workbenchHeight: CGFloat = 320
    static let workbenchMinHeight: CGFloat = 160
    /// Room the conversation and the composer keep above the workbench.
    static let conversationAboveWorkbenchMinHeight: CGFloat = 240
    /// How much of the conversation a shade covers.
    static let shadeHeightShare: CGFloat = 0.62
}
