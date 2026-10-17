import Foundation

/// How close a context window is to full, at the same 90% point where the design system's
/// `ContextUsageRing` turns red.
enum ContextPressure: Hashable {
    case normal
    /// Past 75%: worth knowing, compaction isn't far off.
    case elevated
    /// Past 90%.
    case critical

    init(fraction: Double) {
        self = fraction > 0.9 ? .critical : fraction > 0.75 ? .elevated : .normal
    }

    var summary: String? {
        switch self {
        case .normal: nil
        case .elevated: "Filling up"
        case .critical: "Nearly full"
        }
    }
}
