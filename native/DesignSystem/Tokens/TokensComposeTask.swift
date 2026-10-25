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
        static let ruleGap: CGFloat = 14
        static let editorGap: CGFloat = 24
        static let editorFont = Font.ds(14)
        static let editorLineSpacing: CGFloat = 7
        /// `editorLineSpacing` in the rich-text editor (`ComposerMetrics.editorRichLineLeading`).
        static let editorRichLineLeading: CGFloat = 5
        static let editorInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        static let editorMaxHeight: CGFloat = 1200
        static let popoverWidth: CGFloat = 372
        static let popoverMaxHeight: CGFloat = 600
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
