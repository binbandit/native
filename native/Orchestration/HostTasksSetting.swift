import Foundation

/// Whether Native's host serves Native's tools to its sessions and runs the tasks they hand each
/// other (docs/durability.md, "Native's tools in the host"): `NativeHostTasks` in the user defaults.
/// With it on, delegated tasks keep working with the app closed, and on a remote host. With it
/// off, the app serves the tools itself, as before the host ran them. It's sent to the host at
/// every connection, so a change applies the next time Native starts.
enum HostTasksSetting {
    static let defaultsKey = "NativeHostTasks"
    static let defaultValue = false

    static var isEnabled: Bool {
        // `bool(forKey:)` also reads a launch argument (`-NativeHostTasks YES`), which arrives as text.
        UserDefaults.standard.object(forKey: defaultsKey) == nil
            ? defaultValue : UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
