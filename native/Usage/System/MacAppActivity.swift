#if os(macOS)
import AppKit

/// Whether Native is the frontmost app.
final class MacAppActivity: AppActivity {
    var isActive: Bool {
        NSApplication.shared.isActive
    }
}
#endif
