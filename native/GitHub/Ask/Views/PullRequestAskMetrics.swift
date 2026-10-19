import SwiftUI

/// The question panel's own sizes; everything else comes from the design system.
enum PullRequestAskMetrics {
    static let panelMinWidth: CGFloat = 320
    static let panelIdealWidth: CGFloat = 400
    static let panelMaxWidth: CGFloat = 640
    /// The question bubble's share of the panel's width.
    static let questionFraction: CGFloat = 0.9
}
