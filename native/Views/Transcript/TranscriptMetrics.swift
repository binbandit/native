import SwiftUI

/// The few sizes only the transcript uses, kept here so its views don't repeat them. Everything
/// else comes from the design system.
nonisolated enum TranscriptMetrics {
    static let promptBubbleRadius: CGFloat = 16
    static let thoughtRailWidth: CGFloat = 2
    static let quoteRailWidth: CGFloat = 3
    static let sessionMessageRailWidth: CGFloat = 3
    static let toolDetailMaxHeight: CGFloat = 266
    static let toolImageMaxHeight: CGFloat = 200
    /// The square an image a user sent is shown in.
    static let attachmentImageSide: CGFloat = 120
    static let planMaxHeight: CGFloat = 220
}
