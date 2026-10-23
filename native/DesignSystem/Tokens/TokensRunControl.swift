import SwiftUI

extension DS {
    /// Run's split control shares Open In's outline and height.
    enum RunControl {
        static let labelMaxWidth: CGFloat = 112
        static let playFont = Font.system(size: 11)
        static let stopFont = Font.system(size: 8)
        static let finishedFont = Font.system(size: 10, weight: .semibold)
        static let playOffset: CGFloat = 0.5
        static let finishedDuration = Duration.milliseconds(1_600)
        static let borderWidth: CGFloat = 1
        /// The 4pt gap plus the system menu's 5pt top inset, matching Open In.
        static let menuOffset: CGFloat = DS.Space.xs + 5
    }
}
