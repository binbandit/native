import SwiftUI

extension DS {
    /// Peek's shell from All in view. The approval and question retain their shared component tokens.
    public nonisolated enum Peek {
        public static let width: CGFloat = 600
        public static let headerHeight: CGFloat = 42
        public static let headerLeading: CGFloat = 16
        public static let headerTrailing: CGFloat = 14
        public static let headerGap: CGFloat = 9
        public static let openGap: CGFloat = 6
        public static let openLeading: CGFloat = 10
        public static let openMargin: CGFloat = 2
        public static let openDividerHeight = DS.Sidebar.keycapHeight
        public static let bodyHorizontal: CGFloat = 20
        public static let bodyVertical: CGFloat = 16
        public static let maxBodyHeight: CGFloat = 560
        public static let windowInset: CGFloat = 24
        /// Clear of the toolbar: Peek never covers the window's title or its subtitle.
        public static let toolbarGap = DS.Space.sm
        /// The arrow sits this far down Peek's edge when there's room, so Peek hangs from its row.
        public static let arrowInset: CGFloat = 40
        public static let arrowDepth: CGFloat = 7
        public static let arrowWidth: CGFloat = 16
        /// Between the row's edge and the arrow's tip.
        public static let arrowGap: CGFloat = 4
        public static let radius = DS.Radius.panel
        public static let titleFont = Font.ds(13, weight: .book)
        public static let openFont = Font.ds(12, weight: .book)
    }
}
