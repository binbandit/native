import SwiftUI

extension DS {
    public nonisolated enum DiffComments {
        public static let referencePaneWidth: CGFloat = 620
        public static let hairline: CGFloat = 1
        public static let gutter: CGFloat = 36
        public static let marker: CGFloat = 16
        public static let anchorInset = gutter * 2 + marker
        public static let lineHeight: CGFloat = 20
        public static let editorMinHeight: CGFloat = 68
        public static let editorHorizontal: CGFloat = 10
        public static let summaryHeight: CGFloat = 38
        public static let headerHeight: CGFloat = 36
        public static let codeFont = DSTypography.font(size: 11.5, design: .mono)
    }
}
