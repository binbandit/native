import Foundation

extension NativePolicy {
    /// Where managed settings live on this platform: forced defaults on macOS, the managed app
    /// configuration on iPadOS.
    public static func platformSource(
        defaults: UserDefaults = .standard, simulatedManagedKeys: Set<String> = []
    ) -> any PolicySource {
        #if os(macOS)
            UserDefaultsPolicySource(defaults: defaults, simulatedManagedKeys: simulatedManagedKeys)
        #else
            ManagedAppConfigurationPolicySource(defaults: defaults)
        #endif
    }
}
