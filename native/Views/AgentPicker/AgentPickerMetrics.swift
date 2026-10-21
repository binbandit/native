import SwiftUI

/// The agent picker's few sizes beyond the design system's, so its views carry no literals.
nonisolated enum AgentPickerMetrics {
    /// Wide enough for a name, its state and its fix on one line, and an install command in two
    /// lines under it.
    static let width: CGFloat = 480
    /// Past this the list scrolls, so the picker fits a short window.
    static let listMaxHeight: CGFloat = 360
}
