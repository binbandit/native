import SwiftUI

extension DS {
    public nonisolated enum ComposerQuote {
        public static let inset: CGFloat = 24
        public static let top: CGFloat = 12
        public static let bottom: CGFloat = 10
        public static let numberGap: CGFloat = 7
        public static let lineHeight: CGFloat = 20
        public static let maxHeight: CGFloat = 180
        public static let headerFont = DSTypography.font(size: 11.5)
        public static let codeFont = DSTypography.font(size: 12, design: .mono)
        public static let numberFont = DSTypography.font(size: 10.5, design: .mono)
    }
}
