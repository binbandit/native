import Intents
import Observation

#if os(macOS)
import Security
#endif

/// The system's Focus status through `INFocusStatusCenter`. That needs the Focus Status capability
/// (`com.apple.developer.focus-status`) and a provisioning profile that grants it: macOS kills an
/// ad hoc signed app that claims the entitlement, and asking without it crashes. So builds without
/// it report `.unavailable` and never touch the API beyond that.
@Observable
final class SystemFocusStatus: FocusStatusProviding {
    private(set) var access: FocusAccess

    @ObservationIgnored private let isEntitled = SystemFocusStatus.hasEntitlement()

    init() {
        access = isEntitled ? Self.access(INFocusStatusCenter.default.authorizationStatus) : .unavailable
    }

    var isFocused: Bool? {
        guard access == .allowed else { return nil }
        return INFocusStatusCenter.default.focusStatus.isFocused
    }

    func requestAccessIfNeeded() async {
        guard isEntitled, access == .notDetermined else { return }
        let status = await withCheckedContinuation { continuation in
            INFocusStatusCenter.default.requestAuthorization { continuation.resume(returning: $0) }
        }
        access = Self.access(status)
    }

    private static func access(_ status: INFocusStatusAuthorizationStatus) -> FocusAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .allowed
        case .denied: .denied
        case .restricted: .unavailable
        @unknown default: .unavailable
        }
    }

    /// Whether this build was signed with the Focus Status entitlement.
    private static func hasEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.focus-status" as CFString, nil)
        return (value as? Bool) == true
        #else
        // iPad builds ship through the App Store with the capability.
        return true
        #endif
    }
}
