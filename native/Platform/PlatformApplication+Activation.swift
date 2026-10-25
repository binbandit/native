import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension PlatformApplication {
    /// Posted when the user comes back to Native.
    static var didBecomeActiveNotification: Notification.Name {
        #if canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }

    /// When the user may have stepped away: Native stops being frontmost, or the display sleeps
    /// (a Mac left with Native in front stays active through a lock).
    static var awayStartNotifications: [(center: NotificationCenter, name: Notification.Name)] {
        #if canImport(AppKit)
        [
            (.default, NSApplication.willResignActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification),
        ]
        #else
        [(.default, UIApplication.willResignActiveNotification)]
        #endif
    }

    /// When the user is back at Native.
    static var awayEndNotifications: [(center: NotificationCenter, name: Notification.Name)] {
        #if canImport(AppKit)
        [
            (.default, NSApplication.didBecomeActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification),
        ]
        #else
        [(.default, UIApplication.didBecomeActiveNotification)]
        #endif
    }
}
