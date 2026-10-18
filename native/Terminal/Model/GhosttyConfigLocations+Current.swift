#if os(macOS)
import AppKit
import Terminal

extension GhosttyConfigLocations {
    /// This user's Ghostty config locations (honoring `XDG_CONFIG_HOME`, which `open` passes on,
    /// so a throwaway config can be tried with `XDG_CONFIG_HOME=/tmp/x scripts/dev/run-isolated.sh`),
    /// with Ghostty.app's themes when it's installed.
    static var current: GhosttyConfigLocations {
        GhosttyConfigLocations(
            environment: ProcessInfo.processInfo.environment, home: .homeDirectory, bundledThemes: ghosttyThemes)
    }

    /// Ghostty.app's bundled themes, wherever the app is installed.
    static var ghosttyThemes: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")?
            .appending(path: "Contents/Resources/ghostty/themes")
    }
}
#endif
