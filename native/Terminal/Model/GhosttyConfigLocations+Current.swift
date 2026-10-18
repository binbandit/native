#if os(macOS)
import AppKit
import Terminal

extension GhosttyConfigLocations {
    /// This user's Ghostty config locations, with Ghostty.app's themes when it's installed.
    ///
    /// `-NativeGhosttyConfigHome <folder>` stands in for `XDG_CONFIG_HOME`, for trying a throwaway
    /// config in a development build (`open` doesn't pass the environment on).
    static var current: GhosttyConfigLocations {
        var environment = ProcessInfo.processInfo.environment
        if let override = UserDefaults.standard.string(forKey: "NativeGhosttyConfigHome") {
            environment["XDG_CONFIG_HOME"] = override
        }
        return GhosttyConfigLocations(environment: environment, home: .homeDirectory, bundledThemes: ghosttyThemes)
    }

    /// Ghostty.app's bundled themes, wherever the app is installed.
    static var ghosttyThemes: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")?
            .appending(path: "Contents/Resources/ghostty/themes")
    }
}
#endif
