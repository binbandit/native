import NativePolicy

/// Plugins that are part of how Native runs rather than features the user picks: they're applied
/// with the enabled plugins but never listed in Settings ▸ Extensions or switched off.
enum SystemPlugins {
    static var current: [any NativePlugin] {
        [PolicyPlugin(policy: PolicyCenter.shared.policy), TelemetrySessionPlugin()]
    }
}
