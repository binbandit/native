import AppKit

/// Runs an action when the Mac wakes or its clock changes: the moments a timer set against wall
/// time can come due without firing.
final class SystemClockEvents {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    init(_ action: @escaping @MainActor @Sendable () -> Void) {
        let sources: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (.default, .NSSystemClockDidChange),
        ]
        observers = sources.map { center, name in
            (center, center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { action() }
            })
        }
    }

    isolated deinit {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
    }
}
