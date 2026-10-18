import CoreFoundation
import NativeTelemetry

/// Notices when the main thread stops answering: two seconds or more of work without getting back
/// to its run loop (where it handles input) is recorded as a hang. It watches the main run loop
/// rather than pinging it, so an idle app never wakes up for it (`docs/performance.md`).
enum TelemetryHangWatchdog {
    nonisolated static let threshold = Duration.seconds(2)

    private static var observer: CFRunLoopObserver?
    /// When the main thread last woke up or came back to its run loop; nil while it sleeps.
    private static var lastCheckpoint: ContinuousClock.Instant?

    static func start() {
        guard observer == nil else { return }
        let activities: CFRunLoopActivity = [.beforeTimers, .beforeWaiting, .afterWaiting]
        let observer = CFRunLoopObserverCreateWithHandler(nil, activities.rawValue, true, 0) { _, activity in
            MainActor.assumeIsolated { reached(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    private static func reached(_ activity: CFRunLoopActivity) {
        let now = ContinuousClock.now
        if activity != .afterWaiting, let lastCheckpoint, now - lastCheckpoint >= threshold {
            Telemetry.record(.hangDetected(duration: now - lastCheckpoint))
        }
        lastCheckpoint = activity == .beforeWaiting ? nil : now
    }
}
