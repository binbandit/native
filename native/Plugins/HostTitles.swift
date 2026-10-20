import Foundation

/// Whether tasks that run in Native's host get their titles there (docs/durability.md, "Titles"):
/// `NativeHostTitles` in the user defaults. With it on, the host writes each task's title from its
/// first message and keeps the user's renames, so a task started with the app closed still gets
/// one; the app mirrors them (`SessionTitles+Host.swift`). With it off, the app writes titles as it
/// did before, and tells the host not to. Read at launch; tasks in the app are titled there either
/// way. Off by default until it's verified in the running app (`-NativeHostTitles YES` turns it on).
enum HostTitles {
    static let defaultsKey = "NativeHostTitles"
    static let defaultValue = false

    static var isEnabled: Bool {
        // `bool(forKey:)` also reads a launch argument (`-NativeHostTitles NO`), which arrives as text.
        UserDefaults.standard.object(forKey: defaultsKey) == nil
            ? defaultValue : UserDefaults.standard.bool(forKey: defaultsKey)
    }
}
