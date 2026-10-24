import SwiftUI

extension DS {
    /// Fine print's field and its single settings popover, from the approved composer mock.
    public nonisolated enum ComposerSettings {
        public static let width: CGFloat = 808
        public static let inputHeight: CGFloat = 52
        public static let textInsets = EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 12)
        public static let trailingInset: CGFloat = 14
        public static let controlHeight: CGFloat = 24
        public static let popoverWidth: CGFloat = 380
        public static let popoverMaxHeight: CGFloat = 620
        public static let popoverInset: CGFloat = 6
        public static let sectionInset: CGFloat = 8
        public static let rowHeight: CGFloat = 26
        public static let selectionWidth: CGFloat = 14
        public static let modelListHeight: CGFloat = 156
        public static let rowFont = DSTypography.font(size: 12.5)
        public static let detailFont = DSTypography.font(size: 11.5)
    }
}
