import SwiftUI

extension DS {
    /// The approved toolbar well: 340 by 30 points, with a reserved trailing progress column.
    public nonisolated enum TaskWell {
        public static let width: CGFloat = 340
        public static let height: CGFloat = 30
        public static let leading: CGFloat = 11
        public static let trailing: CGFloat = 12
        public static let gap: CGFloat = 9
        public static let textGap: CGFloat = 6
        public static let signal: CGFloat = 14
        public static let dividerInset: CGFloat = 10
        public static let tickWidth: CGFloat = 1.6
        public static let tickGap: CGFloat = 1.4
        public static let tickHeight: CGFloat = 9
        public static let tickRadius: CGFloat = 0.6
        public static let maxTicks = 12
        public static let titleMaxWidth: CGFloat = 220
        public static let titleMinWidth: CGFloat = 40
        public static let panelWidth: CGFloat = 360
        public static let rowHeight: CGFloat = 34
        public static let rowIconWidth: CGFloat = 22
        public static let rowTitleWidth: CGFloat = 104
        public static let lightHeight: CGFloat = 1
        public static let lightWidthShare: CGFloat = 0.24
        public static let lightDuration: Double = 1
        public static let lightPeak: Double = 0.92
        public static let seenDelay: Duration = .seconds(1)
        public static let body = DSTypography.font(size: 12, weight: .book)
        public static let object = DSTypography.font(size: 11.5, weight: .book, design: .mono)
        public static let row = DSTypography.font(size: 12.5, weight: .book)
    }
}
