import SwiftUI

extension DS {
    /// Peek's shell from All in view. The approval and question retain their shared component tokens.
    public nonisolated enum Peek {
        public static let width: CGFloat = 600
        public static let headerHeight: CGFloat = 42
        public static let headerLeading: CGFloat = 16
        public static let headerTrailing: CGFloat = 14
        public static let headerGap: CGFloat = 9
        public static let bodyHorizontal: CGFloat = 20
        public static let bodyVertical: CGFloat = 16
        public static let maxBodyHeight: CGFloat = 560
        public static let windowInset: CGFloat = 24
        public static let titleFont = Font.ds(13, weight: .book)
        public static let openFont = Font.ds(12, weight: .book)
    }
}
