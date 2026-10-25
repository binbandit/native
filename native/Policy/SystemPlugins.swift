import NativePolicy

/// Plugins that are part of how Native runs rather than features the user picks: they're applied
/// with the enabled plugins but never listed in Settings ▸ Extensions or switched off. Restricted
/// mode admits each by the capabilities it declares, like any other plugin.
enum SystemPlugins {
    static func current(policy: NativePolicy) -> [any NativePlugin] {
        [PolicyPlugin(policy: policy), TelemetrySessionPlugin(), TaskScriptsSessionPlugin()]
    }
}
