import SwiftUI

extension ContextGroup {
    /// Fixed per group, never by rank, so a group keeps its color whatever else is in the window.
    var color: Color {
        switch self {
        case .conversation: .dsChart1
        case .configured: .dsChart2
        case .builtIn: .dsChart3
        }
    }
}

extension ContextComposition.Segment.Kind {
    var color: Color {
        switch self {
        case .used(let group): group.color
        // The free space is the bar's own track; the buffer is reserved, so it reads as neither.
        case .free: .dsSelected
        case .buffer: .dsTextQuaternary
        }
    }
}
