import SwiftUI

extension DS {
    nonisolated enum ComposeTask {
        static let width: CGFloat = 680
        static let labelWidth: CGFloat = 40
        static let labelGap: CGFloat = 18
        static let topInset: CGFloat = 40
        static let titleGap: CGFloat = 18
        static let titleHeight: CGFloat = 48
        static let rowHeight: CGFloat = 30
        /// An agent on the To line once there are two.
        static let tokenHeight: CGFloat = 24
        static let tokenPadding: CGFloat = 8
        static let ruleGap: CGFloat = 14
        static let editorGap: CGFloat = 24
        static let editorFont = Font.ds(14)
        static let editorLineSpacing: CGFloat = 7
        /// `editorLineSpacing` in the rich-text editor (`ComposerMetrics.editorRichLineLeading`).
        static let editorRichLineLeading: CGFloat = 5.5
        static let editorInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        static let attachmentGlyph = Font.ds(15)
        static let attachmentHeight: CGFloat = 28
        static let attachmentInset: CGFloat = 9
        static let editorMaxHeight: CGFloat = 1200
        static let popoverWidth: CGFloat = 372
        static let popoverMaxHeight: CGFloat = 600
        /// However little room is left below its control, a popover shows a few rows before it scrolls.
        static let popoverMinHeight: CGFloat = 120
        /// A popover starts this far left of its control's text, and this far below its row.
        static let popoverLeading: CGFloat = 10
        static let popoverGap: CGFloat = 6
        /// Its arrow, whose tip sits this far in from the popover's leading edge.
        static let popoverArrowTip: CGFloat = 30
        static let popoverArrowWidth: CGFloat = 16
        static let popoverArrowHeight: CGFloat = 8
        /// The open control's highlight reaches this far past its text, at this height.
        static let focusInset: CGFloat = 7
        static let focusHeight: CGFloat = 26
        /// Notes under an address line (why a device is offline), at an 18pt line and a short measure.
        static let noteLineSpacing: CGFloat = 3
        static let noteWidth: CGFloat = 540
        /// The Return hint on the page's primary buttons.
        static let keyHintOpacity: Double = 0.5
        static let foldOffset: CGFloat = -22
        static let foldOpacity: Double = 0.28
        static let settlingOpacity: Double = 0.55
        static let messageOffset: CGFloat = 24
        static let composerOffset: CGFloat = 34
        static let fold = Animation.easeOut(duration: 0.12)
        static let settle = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.24)
        static let foldDuration: Duration = .milliseconds(120)
        static let settleDuration: Duration = .milliseconds(240)
    }
}
