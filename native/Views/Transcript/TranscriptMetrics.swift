import SwiftUI

/// The few sizes only the transcript uses, kept here so its views don't repeat them. Everything
/// else comes from the design system.
nonisolated enum TranscriptMetrics {
    static let promptBubbleRadius = DS.Radius.message
    static let thoughtRailWidth: CGFloat = 2
    static let quoteRailWidth: CGFloat = 3
    static let sessionMessageRailWidth: CGFloat = 3
    static let toolDetailMaxHeight: CGFloat = 266
    /// An open group of tool work shows about eleven and a half rows before it scrolls, so the
    /// cut-off row says it does.
    static let toolGroupListHeight: CGFloat = 276
    static let toolImageMaxHeight: CGFloat = 200
    /// An image a user sent is shown whole, this tall (less when it's very wide).
    static let attachmentImageHeight: CGFloat = 140
    static let attachmentImageMaxWidth: CGFloat = 280
    static let planMaxHeight: CGFloat = 220
}
