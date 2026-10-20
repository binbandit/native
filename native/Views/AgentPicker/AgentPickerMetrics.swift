#if NATIVE_AGENT_PICKER_WIP
import SwiftUI

/// The agent picker's few sizes beyond the design system's, so its views carry no literals.
nonisolated enum AgentPickerMetrics {
    /// Wide enough for a name, its state and its fix on one line, and an install command in two
    /// lines under it.
    static let width: CGFloat = 480
    /// How far below the window's top it floats: the command palette's place, so the two read as one
    /// kind of thing.
    static let topInset: CGFloat = 72
    /// Past this the list scrolls, so the picker fits a short window.
    static let listMaxHeight: CGFloat = 360
}
#endif
