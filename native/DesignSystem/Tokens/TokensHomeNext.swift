import SwiftUI

extension DS {
    /// Next's single reading column, matched to the approved Home drawing.
    public enum HomeNext {
        public static let column: CGFloat = 800
        public static let top: CGFloat = 64
        public static let headerHeight: CGFloat = 20
        public static let askTop: CGFloat = 26
        public static let askBottom: CGFloat = 18
        public static let titleTop: CGFloat = 10
        public static let sectionTop: CGFloat = 22
        public static let statusTop: CGFloat = 14
        public static let rowInset: CGFloat = 7
        public static let rowHeight: CGFloat = 46
        public static let finishedHeight: CGFloat = 34
        public static let titleTracking: CGFloat = -0.95
        public static let ledeTracking: CGFloat = -0.22
        public static let titleFont = Font.ds(30, weight: .medium)
        public static let ledeFont = Font.ds(15)
        public static let rise: CGFloat = 12
        public static let pageSize = 5
    }
}
