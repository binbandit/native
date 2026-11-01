import SwiftUI

extension DS {
    /// Plainly: the approved Settings frame, measured at a 1440 by 900 window.
    enum Settings {
        static let pageWidth: CGFloat = 640
        static let pageTopInset = Space.xl
        static let rowHeight: CGFloat = 44
        static let rowTitleHeight: CGFloat = 18
        static let rowLabelMinWidth: CGFloat = 120
        static let rowInset = Space.xl
        static let rowVerticalInset: CGFloat = 9
        static let navRowHeight: CGFloat = 30
        static let navGap: CGFloat = 10
        static let navGroupGap = Space.xl
        static let navRowGap = Space.xxs
        static let navInset: CGFloat = 10
        static let searchBottomInset: CGFloat = 14
        static let controlHeight: CGFloat = 26
        static let wideControl: CGFloat = 224
        static let scopeWidth: CGFloat = 220
        static let body = Font.ds(13)
        static let groupTitle = Font.ds(13, weight: .medium)
        static let navGroup = Font.ds(11.5, weight: .medium)
        static let caption = Font.ds(12)
        static let sourceStackWidth: CGFloat = 372
        static let sourceColumnWidth: CGFloat = 150
        static let contextBarHeight: CGFloat = 4
        static let contextLegendSize: CGFloat = 8
        /// New Tasks' load rows: one right-aligned column of token counts, then one fixed slot for
        /// a switch, a lock or nothing, so every row's trailing edge lines up.
        static let loadTokenColumn: CGFloat = 48
        static let loadControlSlot: CGFloat = 40
        /// Group widths under which every New Tasks row narrows the same way: first each source tag
        /// shrinks to its glyph, then every value moves under its label.
        static let compactSourcesBelow: CGFloat = 540
        static let stackedRowsBelow: CGFloat = 420
        static let scopeCompactWidth: CGFloat = 174
        static let hairline: CGFloat = 1
    }
}
