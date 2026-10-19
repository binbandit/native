import SwiftUI

/// The AI Instructions feature's own dimensions.
nonisolated enum AIInstructionMetrics {
    /// A preview grows with what was written up to this, then scrolls; an agent's whole prompt is long.
    static let previewMaxHeight: CGFloat = 220
}
