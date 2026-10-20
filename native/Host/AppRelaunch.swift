#if os(macOS)
import AppKit

/// Opens a fresh copy of Native with this one's arguments, then quits this one: for settings that
/// apply at launch.
enum AppRelaunch {
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }
}
#endif
