import SwiftUI

extension DS {
    /// Fine print's field and its single settings popover, from the approved composer mock.
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
        public static let popoverMaxHeight: CGFloat = 620
        public static let popoverInset: CGFloat = 6
        public static let sectionInset: CGFloat = 8
        /// A row: 26pt with the pointer, a full touch target on iPadOS.
        public static let rowHeight: CGFloat = isTouch ? 44 : 26
        /// The gutter that holds a row's check, lock or loader.
        public static let selectionWidth: CGFloat = 14
        /// Where every name, header, caption, filter and footer starts, in from a row's edge: the
        /// row's padding, the gutter and the gap after it.
        public static let textLeading: CGFloat = DS.Space.md + selectionWidth + DS.Space.sm
        /// The rule between sections, in from the popover's edges.
        public static let ruleInset: CGFloat = popoverInset + DS.Space.md
        /// A header's line, and each line of a caption.
        public static let lineHeight: CGFloat = 16
        /// The effort control.
        public static let segmentedHeight: CGFloat = isTouch ? DS.Size.controlMD : DS.Size.controlXS
        /// A change the agent confirms within this shows no loader.
        public static let applyingDelay: Duration = .milliseconds(150)
        public static let agentReceiptMinHeight: CGFloat = 40
        public static let managedFooterReserve: CGFloat = 76
        public static let emptyModelsReserve: CGFloat = 40
        public static let sectionsReserve: CGFloat = 124
        public static let modelCaptionHeight: CGFloat = lineHeight * 2 + DS.Space.xxs
        public static let rowFont = DSTypography.font(size: isTouch ? 13 : 12.5)
        /// The characters a filter matched in a name.
        public static let rowMatchFont = DSTypography.font(size: isTouch ? 13 : 12.5, weight: .semibold)
        public static let detailFont = DSTypography.font(size: 11.5)
        public static let detailMediumFont = DSTypography.font(size: 11.5, weight: .medium)
        public static let segmentFont = DSTypography.font(size: isTouch ? 12 : 11.5)
        public static let segmentSelectedFont = DSTypography.font(size: isTouch ? 12 : 11.5, weight: .medium)
        public static let checkFont = DSTypography.font(size: 12, weight: .semibold)
        public static let lockFont = DSTypography.font(size: 11)
        public static let glyphFont = DSTypography.font(size: 10, weight: .semibold)
    }
}
