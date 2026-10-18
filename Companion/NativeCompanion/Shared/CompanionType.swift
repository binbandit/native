import SwiftUI

/// The phone's type scale: the design system's families at iPhone reading sizes (its own scale is
/// the Mac's 12–13pt). Candidates for touch tokens in the design system once the iPad needs them.
enum CompanionType {
    static let largeTitle = Font.ds(30, weight: .semibold)
    static let title = Font.ds(22, weight: .semibold)
    static let headline = Font.ds(17, weight: .medium)
    static let body = Font.ds(16)
    static let bodyMedium = Font.ds(16, weight: .medium)
    static let callout = Font.ds(15)
    static let subheadline = Font.ds(14)
    static let caption = Font.ds(13)
    static let captionMedium = Font.ds(13, weight: .medium)
    static let mono = Font.ds(14, design: .mono)
    static let code = Font.ds(34, weight: .medium, design: .mono)
}

/// The phone's few layout sizes beyond the design system's spacing.
enum CompanionMetrics {
    static let hostMark: CGFloat = 32
    static let welcomeMark: CGFloat = 72
    static let hostMarkSmall: CGFloat = 20
    static let hostMarkTiny: CGFloat = 14
    static let iconThumbnail: CGFloat = 36
    static let iconPreview: CGFloat = 60
    static let scannerHeight: CGFloat = 320
    static let pill: CGFloat = 50
    static let composerMaxLines = 6
    static let readableWidth: CGFloat = 640
}
