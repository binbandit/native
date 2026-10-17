import Foundation

/// Where goals, workflow runs and automations are kept: Application Support, unless the
/// `automationDataDirectory` default points elsewhere. The override keeps test runs and development
/// builds out of the user's own data (`-automationDataDirectory /tmp/…` on the command line).
public nonisolated enum AutomationStorage {
    public static var directory: URL {
        if let path = UserDefaults.standard.string(forKey: "automationDataDirectory"), !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "Native", directoryHint: .isDirectory)
    }

    public static func file(_ name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }
}
