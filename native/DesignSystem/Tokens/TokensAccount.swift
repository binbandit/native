import SwiftUI

extension DS {
    /// The quiet GitHub identity shared by the sidebar and Settings.
    enum Account {
        static let avatarSize: CGFloat = 20
        static let avatarBorder: CGFloat = 0.5
        static let initials = Font.ds(9, weight: .semibold)
        static let nameTracking: CGFloat = -0.13
        static let settingsGlyph = Font.system(size: 14)

        static func avatarStroke(in scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.12)
        }
    }
}
