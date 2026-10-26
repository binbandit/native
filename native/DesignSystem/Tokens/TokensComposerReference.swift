import SwiftUI

extension DS {
    /// The inline file mention in both the composer and the Compose page (.men in the mock).
    nonisolated enum ComposerReference {
        static let pathFont = DSTypography.font(size: 10.5, design: .mono)
        static let fontSize: CGFloat = 12.5
        static let font = DSTypography.font(size: fontSize, design: .mono)
        static let verticalInset: CGFloat = 1
        /// Nonbreaking spaces keep the padding even when the chip starts a wrapped line.
        static let padding = "\u{00A0}"
        static let paddingFont = DSTypography.font(size: DS.Space.xs * 2, design: .mono)
    }
}
