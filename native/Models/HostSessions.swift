import Foundation

/// Whether agents and their sessions run in Native's background host (docs/durability.md, Phase 2)
/// instead of inside the app: `NativeHostSessions` in the user defaults, one choice for every
/// channel. It's read at launch, so a change applies the next time Native starts.
///
/// With it on, the app hands `AppModel.connectHost(client:)` its host connection before starting,
/// and every agent runtime and session goes through it. With it off, or when no host can be
/// reached, agents run in the app exactly as before.
enum HostSessions {
    static let defaultsKey = "NativeHostSessions"
    /// Off until the host-backed path has proven itself end to end.
    static let defaultValue = false

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }
}
