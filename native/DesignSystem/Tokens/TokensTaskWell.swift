import SwiftUI

extension DS {
    /// The approved toolbar well: 340 by 30 points, with a reserved trailing progress column.
    public nonisolated enum TaskWell {
        public static let changesHeaderHeight: CGFloat = 44
        public static let width: CGFloat = 340
        /// The narrow window's well: the count without "Changed", progress without the agent.
        public static let compactWidth: CGFloat = 180
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
        public static let titleMinWidth: CGFloat = 40
        /// Room occupied by the window controls, sidebar and search before the task title.
        public static let leadingToolbarWidth: CGFloat = 180
        public static let panelWidth: CGFloat = 500
        public static let panelHeaderHeight: CGFloat = 42
        public static let panelHeaderLeading: CGFloat = 15
        public static let panelHeaderTrailing: CGFloat = 14
        public static let contextRing: CGFloat = 13
        public static let footerHeight: CGFloat = 38
        public static let workbenchBarHeight: CGFloat = 36
        public static let devMaxHeight: CGFloat = 320
        /// Keeps the status, worker and checkout visible even with many plugin tools.
        public static let toolsMaxHeight: CGFloat = 320
        public static let rowHeight: CGFloat = 34
        public static let rowIconWidth: CGFloat = 22
        public static let rowTitleWidth: CGFloat = 104
        public static let rowTrailing: CGFloat = 10
        public static let lightHeight: CGFloat = 1
        public static let lightWidthShare: CGFloat = 0.24
        public static let lightDuration: Double = 1
        public static let lightPeak: Double = 0.92
        public static let seenDelay: Duration = .seconds(1)
        public static let body = DSTypography.font(size: 12, weight: .book)
        public static let object = DSTypography.font(size: 11.5, weight: .book, design: .mono)
        /// The open well's quiet facts: context use and the checkout.
        public static let caption = DSTypography.font(size: 11.5, weight: .book)
        /// Steps not yet done, dimmer than the quaternary text they're drawn in.
        public static let tickPendingOpacity = 0.55
        public static let row = DSTypography.font(size: 12.5, weight: .book)
        public static let rowDetail = DSTypography.font(size: 12.5)
        public static let shortcut = DSTypography.font(size: 10.5, design: .mono)
        /// The title's popover: the task's name, then who and where it runs.
        public static let titlePanelWidth: CGFloat = 340
        public static let titleLabelWidth: CGFloat = 58
    }
}
