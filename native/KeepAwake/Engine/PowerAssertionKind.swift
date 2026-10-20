import IOKit.pwr_mgt
import NativeHostProtocol

extension PowerAssertionKind {
    /// IOKit's name for it; nil for a kind this build doesn't know.
    var ioKitType: String? {
        switch self {
        case .preventIdleSleep: kIOPMAssertionTypePreventUserIdleSystemSleep
        case .preventSystemSleep: kIOPMAssertionTypePreventSystemSleep
        case .preventDisplaySleep: kIOPMAssertionTypePreventUserIdleDisplaySleep
        case .unknown: nil
        }
    }
}
