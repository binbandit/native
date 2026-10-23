#if DEBUG
import Foundation

/// Deterministic checks in an isolated Debug instance without changing system accessibility
/// preferences or breaking the host's storage. The ordinary request still comes from its agent.
enum ApprovalPreviewOverride: String {
    case instructionFailure = "instruction-failure"
    case reconnecting
    case reducedMotion = "reduced-motion"

    static var current: Self? {
        UserDefaults.standard.string(forKey: "nativeApprovalPreview").flatMap(Self.init(rawValue:))
    }
}
#endif
