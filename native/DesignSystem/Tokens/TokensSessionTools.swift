import CoreGraphics

/// The session tools' layout sizes, in one place; everything visual comes from the design system.
extension DS {
    public nonisolated enum SessionTools {
        /// The side panel's widths: the floor fits a diff's file list, the ideal a readable diff.
        public static let sidePanelMinWidth: CGFloat = 340
        public static let sidePanelIdealWidth: CGFloat = 420
        public static let sidePanelMaxWidth: CGFloat = 720
        /// The narrowest the conversation gets beside the side panel. Narrower, and a side tool opens over
        /// the conversation instead: at 440pt the conversation wrapped most lines of a reply and the
        /// composer's pills.
        public static let conversationBesidePanelMinWidth: CGFloat = 520
        /// A place's tab strip, and a shade's header.
        public static let stripHeight: CGFloat = max(DS.Size.controlMD + DS.Space.xs, DS.minimumHitTarget)
        /// How much of the conversation a shade covers.
        public static let shadeHeightShare: CGFloat = 0.62
    }
}
