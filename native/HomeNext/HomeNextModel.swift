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
    @ObservationIgnored private var observers: [(NotificationCenter, any NSObjectProtocol)] = []
    @ObservationIgnored private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        let starts = PlatformApplication.awayStartNotifications.map { ($0, true) }
        let ends = PlatformApplication.awayEndNotifications.map { ($0, false) }
        observers = (starts + ends).map { source, leaving in
            (
                source.center,
                source.center.addObserver(forName: source.name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { leaving ? self?.left() : self?.returned() }
                }
            )
        }
    }

    isolated deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    /// The first sign of leaving starts the absence; a display sleeping after the app went to the
    /// background doesn't move it later.
    func left() {
        if awaySince == nil { awaySince = now() }
    }

    func returned() {
        guard let since = awaySince else { return }
        awaySince = nil
        let end = now()
        guard end.timeIntervalSince(since) >= HomeNextAway.minimumLength else { return }
        away = countAway(since, end)
    }
}
