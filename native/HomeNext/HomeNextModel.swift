import Foundation
import Observation

/// Home's state that outlives the page: when the user stepped away, and requests to focus the start
/// field. The page itself can be closed while either happens.
@Observable
final class HomeNextModel {
    /// The last absence long enough to be news, counted when the user came back.
    var away: HomeNextAway?
    /// ⌘N on Home writes in the start field instead of opening another surface.
    var startFieldFocusRequests = 0
    #if DEBUG
    /// Inert fixtures stand in for Usage's shared limits, which persist to disk.
    var fixtureLimits: [HomeNextLimit]?
    #endif
    /// Counts what happened between `start` and `end`; set by the app, which owns the tasks.
    @ObservationIgnored var countAway: @MainActor (_ start: Date, _ end: Date) -> HomeNextAway? = { _, _ in nil }

    @ObservationIgnored private var awaySince: Date?
    @ObservationIgnored private var isInBackground = false
    @ObservationIgnored private var isDisplayAsleep = false
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        var sources: [(NotificationCenter, Notification.Name, @MainActor (HomeNextModel) -> Void)] = [
            (.default, PlatformApplication.willResignActiveNotification, { $0.setInBackground(true) }),
            (.default, PlatformApplication.didBecomeActiveNotification, { $0.setInBackground(false) }),
        ]
        if let display = PlatformApplication.displaySleepNotifications {
            sources.append((display.center, display.sleep, { $0.setDisplayAsleep(true) }))
            sources.append((display.center, display.wake, { $0.setDisplayAsleep(false) }))
        }
        observers = sources.map { center, name, change in
            (
                center,
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let self { change(self) } }
                }
            )
        }
    }

    isolated deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    func setInBackground(_ value: Bool) {
        isInBackground = value
        update()
    }

    func setDisplayAsleep(_ value: Bool) {
        isDisplayAsleep = value
        update()
    }

    /// Away from the first sign of leaving until the user is back at Native: in front, display awake.
    private func update() {
        let isAway = isInBackground || isDisplayAsleep
        if isAway {
            if awaySince == nil { awaySince = now() }
            return
        }
        guard let since = awaySince else { return }
        awaySince = nil
        let end = now()
        guard end.timeIntervalSince(since) >= HomeNextAway.minimumLength else { return }
        away = countAway(since, end)
    }
}
