import SwiftUI

extension DS {
    /// One brief sent to two agents: the outcome card, Compare and the sidebar group.
    nonisolated enum TaskPair {
        /// The agent's name column on the outcome card.
        static let nameWidth: CGFloat = 150
        static let rowHeight: CGFloat = 40
        /// Compare's two version headers and its file rows.
        static let versionHeight: CGFloat = 52
        static let fileRowHeight: CGFloat = 36
        static let columnGap: CGFloat = 16
        static let pagePadding: CGFloat = 24
        /// How far a pair's tasks sit in from the group's heading in the sidebar.
        static let memberIndent: CGFloat = 22
    }
}
