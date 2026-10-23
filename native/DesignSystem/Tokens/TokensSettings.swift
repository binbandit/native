import SwiftUI

extension DS {
    /// Plainly: the approved Settings frame, measured at a 1440 by 900 window.
    enum Settings {
        static let pageWidth: CGFloat = 640
        static let pageTopInset = Space.xl
        static let rowHeight: CGFloat = 44
        static let rowInset = Space.xl
        static let rowVerticalInset: CGFloat = 9
        static let navRowHeight: CGFloat = 30
        static let navGap: CGFloat = 10
        static let navGroupGap = Space.xl
        static let navRowGap = Space.xxs
        static let navInset: CGFloat = 10
        static let controlHeight: CGFloat = 26
        static let wideControl: CGFloat = 224
        static let scopeWidth: CGFloat = 220
        static let body = Font.ds(13)
        static let groupTitle = Font.ds(13, weight: .medium)
        static let navGroup = Font.ds(11.5, weight: .medium)
        static let caption = Font.ds(12)
        static let hairline: CGFloat = 1
    }
}
