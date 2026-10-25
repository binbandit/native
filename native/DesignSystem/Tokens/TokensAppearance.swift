import SwiftUI

extension DS {
    enum Appearance {
        static let swatch: CGFloat = 12
        static let swatchStrokeOpacity = 0.42
        static let chipWidth: CGFloat = 30
        static let chipHeight: CGFloat = 18
        static let chipRadius: CGFloat = 5
        static let tickWidth: CGFloat = 3
        static let tickHeight: CGFloat = 9
        static let tickRadius: CGFloat = 1.5
        static let tickGap: CGFloat = 2.5
        static let headerHeight: CGFloat = 16
        static let numberWidth: CGFloat = 30
        static let markerWidth: CGFloat = 14
        static let numberOpacity = 0.55
        static let separatorOpacity = 0.12
        static let wellBottom: CGFloat = 10
        static let fadeWidth: CGFloat = 28
        static let lockWidth: CGFloat = 340
    }
}

extension DS {
    /// Try On's panel, in the sidebar's column.
    enum TryOn {
        static let rowHeight: CGFloat = 30
        static let rowGap: CGFloat = 10
        static let headerLeading: CGFloat = 18
        static let subtitleGap: CGFloat = 3
        static let controlInset: CGFloat = 14
        static let controlGap: CGFloat = 10
        static let sectionGap: CGFloat = 14
        static let footerBottom: CGFloat = 14
    }
}
