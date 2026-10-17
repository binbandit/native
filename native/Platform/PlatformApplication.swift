#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The running app, as the platform sees it.
@MainActor
enum PlatformApplication {
    /// Whether the user is looking at Native right now, so news can show in the window instead of
    /// as a notification.
    static var isActive: Bool {
        #if canImport(AppKit)
        NSApplication.shared.isActive
        #elseif canImport(UIKit)
        UIApplication.shared.applicationState == .active
        #else
        false
        #endif
    }
}
