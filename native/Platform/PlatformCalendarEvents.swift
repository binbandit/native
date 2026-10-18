import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Runs an action whenever "today" may have changed under the app: midnight, a time-zone change, a
/// manual clock change, waking from sleep, or coming back to the foreground. Date-based appearance
/// (celebrations) recomputes on these, so a timer that slept through its boundary can't leave a
/// stale edition showing.
@MainActor
final class PlatformCalendarEvents {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    init(_ action: @escaping @MainActor () -> Void) {
        var sources: [(NotificationCenter, Notification.Name)] = [
            (.default, .NSCalendarDayChanged),
            (.default, .NSSystemTimeZoneDidChange),
        ]
        #if canImport(AppKit)
        sources += [
            (.default, .NSSystemClockDidChange),
            (.default, NSApplication.didBecomeActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
        ]
        #elseif canImport(UIKit)
        sources += [
            (.default, UIApplication.significantTimeChangeNotification),
            (.default, UIApplication.didBecomeActiveNotification),
        ]
        #endif
        observers = sources.map { center, name in
            (
                center,
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { action() }
                }
            )
        }
    }

    isolated deinit {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
    }
}
