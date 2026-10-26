import SwiftUI

extension DS {
    /// The inline file mention in both the composer and the Compose page (.men in the mock).
    nonisolated enum ComposerReference {
        static let pathFont = DSTypography.font(size: 10.5, design: .mono)
        static let font = DSTypography.font(size: 12.5, design: .mono)
        static let verticalInset: CGFloat = 1
        /// En spaces reserve four points on each edge without changing the canonical @path.
        static let padding = "\u{2002}"
        static let paddingFont = DSTypography.font(size: DS.Space.xs * 2, design: .mono)
    }
}
