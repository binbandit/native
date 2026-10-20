#if DEBUG && NATIVE_SESSION_CHROME_WIP
import CoreGraphics

/// The session chrome's layout sizes, in one place; everything visual comes from the design system.
nonisolated enum SessionChromeMetrics {
    /// The side panel's widths: the floor fits three tabs, the ideal a diff's file list.
    static let sidePanelMinWidth: CGFloat = 340
    static let sidePanelIdealWidth: CGFloat = 420
    static let sidePanelMaxWidth: CGFloat = 720
    /// A place's tab strip.
    static let stripHeight: CGFloat = DS.Size.controlMD + DS.Space.xs
    /// The workbench's pane, open: where it starts, and the least it shrinks to.
    static let workbenchHeight: CGFloat = 320
    static let workbenchMinHeight: CGFloat = 160
    /// Room the conversation and composer keep above the workbench or under a shade.
    static let conversationMinHeight: CGFloat = 240
    /// How much of the conversation a header tool's shade covers.
    static let shadeHeightShare: CGFloat = 0.62
    /// The tools editor and its map.
    static let editorWidth: CGFloat = 640
    static let editorSideWidth: CGFloat = 188
    static let editorConversationHeight: CGFloat = 88
    static let editorChipMinWidth: CGFloat = 120
    /// The dashes outlining a place in the editor, as the composer's drop target draws them.
    static let editorDash: [CGFloat] = [4, 3]
}
#endif
