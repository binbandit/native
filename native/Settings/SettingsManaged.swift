import NativePolicy
import SwiftUI

extension EnvironmentValues {
    /// Why the settings rows inside can't be changed, such as "Managed by your organization".
    @Entry var settingsLockReason: String?
}

extension View {
    /// Locks the row when the organization manages `key`: its control is disabled and the row says
    /// who decides.
    func settingsManaged(by key: PolicyKey) -> some View {
        modifier(SettingsManagedModifier(key: key))
    }

    /// Locks the row for `reason` (nil leaves it as it is).
    func settingsLocked(_ reason: String?) -> some View {
        transformEnvironment(\.settingsLockReason) { current in
            if let reason { current = reason }
        }
    }
}

private struct SettingsManagedModifier: ViewModifier {
    let key: PolicyKey
    @Environment(PolicyCenter.self) private var policy: PolicyCenter?

    func body(content: Content) -> some View {
        content.settingsLocked(policy?.isManaged(key) == true ? PolicyCenter.managedExplanation : nil)
    }
}
