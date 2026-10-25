import SwiftUI

extension DS {
    /// The quiet GitHub identity shared by the sidebar and Settings.
    enum Account {
        static let avatarSize: CGFloat = 20
        static let avatarBorder: CGFloat = 0.5
        static let initials = Font.ds(9, weight: .semibold)
        static let nameTracking: CGFloat = -0.13
        static let settingsGlyph = Font.system(size: 14)

        // The footer's account popover: who you are, who else you could be, and who manages Native.
        static let menuWidth: CGFloat = 300
        static let managedWidth: CGFloat = 340
        static let menuAvatarSize: CGFloat = 26
        static let menuInset: CGFloat = 6
        static let menuRowHeight: CGFloat = 24
        static let menuRowRadius: CGFloat = 8
        static let menuLoginFont = Font.ds(11.5, weight: .book, design: .mono)
        static let managedInset: CGFloat = 16
        static let managedLeading = menuInset + DS.Space.md
        static let managedKeyWidth: CGFloat = 84
        static let footerHeight: CGFloat = 52
        static let footerLeading: CGFloat = 13
        static let footerTrailing: CGFloat = 16
        static let footerTrailingGlyph = Font.system(size: 10, weight: .semibold)

        static func avatarStroke(in scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.12)
        }
    }
}
