import SwiftUI

extension DS {
    /// Shared message fields, compact picker rows and agent change receipts.
    public nonisolated enum ComposerSettings {
        /// iPadOS: the same type and colors at full touch targets (`DS.isTouchPlatform`, which tokens
        /// can't read off the main actor).
        private static let isTouch: Bool = {
            #if os(iOS)
            true
            #else
            false
            #endif
        }()
        public static let width: CGFloat = 808
        public static let inputHeight: CGFloat = 52
        public static let textInsets = EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 12)
        public static let trailingInset: CGFloat = 14
        public static let controlHeight: CGFloat = 24
        public static let popoverWidth: CGFloat = 380
        public static let popoverInset: CGFloat = 6
        public static let sectionInset: CGFloat = 8
        /// A row: 26pt with the pointer, a full touch target on iPadOS.
        public static let rowHeight: CGFloat = isTouch ? 44 : 26
        public static let selectionWidth: CGFloat = 14
        /// A change the agent confirms within this shows no loader.
        public static let applyingDelay: Duration = .milliseconds(150)
        public static let agentReceiptMinHeight: CGFloat = 40
        public static let rowFont = DSTypography.font(size: isTouch ? 13 : 12.5)
        public static let detailFont = DSTypography.font(size: 11.5)
    }
}
