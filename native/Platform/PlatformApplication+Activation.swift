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

    /// Posted when Native stops being frontmost, or its device locks.
    static var willResignActiveNotification: Notification.Name {
        #if canImport(AppKit)
        NSApplication.willResignActiveNotification
        #else
        UIApplication.willResignActiveNotification
        #endif
    }

    /// The display going to sleep and waking, where a Mac left with Native in front stays active
    /// through a lock. iPad apps resign active instead, so there's nothing extra to watch there.
    static var displaySleepNotifications:
        (center: NotificationCenter, sleep: Notification.Name, wake: Notification.Name)?
    {
        #if canImport(AppKit)
        (
            NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.screensDidWakeNotification
        )
        #else
        nil
        #endif
    }
}
