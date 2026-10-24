import SwiftUI

extension DS {
    /// All in view, measured from the selected sidebar reference at its 256pt width.
    public nonisolated enum Sidebar {
        public static let inset: CGFloat = 8
        public static let leading: CGFloat = 6
        public static let trailing: CGFloat = 10
        public static let rowVertical: CGFloat = 7
        public static let rowHeight: CGFloat = 30
        public static let titleHeight: CGFloat = 16
        public static let askGap: CGFloat = 3
        public static let askLineSpacing: CGFloat = 2
        public static let askLineHeight: CGFloat = 17
        public static let headerHeight: CGFloat = 26
        public static let headerLeading: CGFloat = 30
        public static let headerTop: CGFloat = 12
        public static let titleTracking: CGFloat = -0.05
        public static let headerTracking: CGFloat = -0.06
        public static let keycapHeight: CGFloat = 16
        public static let keycapRadius: CGFloat = 3
        public static let keycapBottom: CGFloat = 1
        public static let projectFont = Font.ds(12, weight: .semibold)
        public static let keycapFont = Font.ds(10, weight: .medium, design: .mono)
        public static let clockFont = Font.ds(11, weight: .medium, design: .mono)
        public static let askCodeFont = Font.ds(11.5, weight: .book, design: .mono)
        public static let attentionWidth: CGFloat = 396
        public static let attentionMaximumHeight: CGFloat = 480
        public static let attentionHeaderTop: CGFloat = 8
        public static let attentionHeaderBottom: CGFloat = 6
        public static let attentionProjectFont = Font.ds(11.5, weight: .semibold)
        public static let attentionCountHeight: CGFloat = 22
        public static let attentionCountLeading: CGFloat = 7
        public static let attentionCountTrailing: CGFloat = 8
        public static let attentionCountRadius: CGFloat = 11
    }

    public nonisolated enum Signal {
        public static let canvas: CGFloat = 240
        public static let centers: [CGFloat] = [50, 120, 190]
        public static let movingRadius: CGFloat = 20
        public static let restingRadius: CGFloat = 7
        public static let stillRadius: CGFloat = 22
        public static let unreadRadius: CGFloat = 240 * 3 / 14
        public static let restRadius: CGFloat = 240 * 2.3 / 14
        public static let breathPeriod: TimeInterval = 2.8
        public static let freshDuration: TimeInterval = 60
        public static let activationDuration: TimeInterval = 4
        public static let breathLow: Float = 0.58
        public static let offlineOpacity: Double = 0.6
        public static let askDuration: TimeInterval = 0.42
        public static let answerDuration: TimeInterval = 0.3
        public static let finishDuration: TimeInterval = 0.5
        public static let ringDelay: TimeInterval = 0.05
        public static let readDuration: TimeInterval = 0.35
        public static let failureDuration: TimeInterval = 0.3
    }
}

extension Animation {
    public nonisolated static let dsSidebarAsk = Animation.spring(duration: DS.Signal.askDuration, bounce: 0.12)
    public nonisolated static let dsSidebarAnswer = Animation.easeOut(duration: DS.Signal.answerDuration)
}
