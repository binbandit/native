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
    static let planMaxHeight: CGFloat = 220
    /// Leading between lines of a Markdown code block and of a tool's output.
    static let codeLineSpacing: CGFloat = 1
    static let outputLineSpacing: CGFloat = 3
}
