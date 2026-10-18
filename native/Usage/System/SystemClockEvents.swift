#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Runs an action when the device wakes or its clock changes: the moments a timer set against
/// wall time can come due without firing.
final class SystemClockEvents {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    init(_ action: @escaping @MainActor @Sendable () -> Void) {
        #if canImport(AppKit)
        let sources: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (.default, .NSSystemClockDidChange),
        ]
        #elseif canImport(UIKit)
        let sources: [(NotificationCenter, Notification.Name)] = [
            (.default, UIApplication.willEnterForegroundNotification),
            (.default, UIApplication.significantTimeChangeNotification),
        ]
        #else
        let sources: [(NotificationCenter, Notification.Name)] = []
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
