#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
// The iPad badge goes through notifications; the Dock tile needs nothing.
import UserNotifications
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

    /// Shows `count` on the app icon (the Dock tile on the Mac); 0 clears it.
    static func setBadgeCount(_ count: Int) async {
        #if canImport(AppKit)
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        #elseif canImport(UIKit)
        let center = UNUserNotificationCenter.current()
        guard count > 0 else {
            try? await center.setBadgeCount(0)
            return
        }

        // Ask only when there is something to show, never at launch. iOS asks once per install, so
        // badge-only authorization here would rule out notification alerts and sounds later.
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted == true else { return }
        try? await center.setBadgeCount(count)
        #endif
    }
}
