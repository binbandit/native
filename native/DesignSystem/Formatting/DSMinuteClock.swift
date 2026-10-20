import Foundation
import Observation

#if canImport(AppKit)
import AppKit
#endif

/// One clock for every label that shows an age to the minute (`CompactAgeText`, Home's recent
/// tasks): it ticks at the start of each minute while the app can be seen, and not at all while
/// it's hidden, minimized or covered, catching up the moment it shows again. Reading `now` in a
/// view's body redraws that view on each tick, so a window of ages costs one wakeup a minute while
/// it's on screen and nothing while it isn't, where a `TimelineView` per label redrew every one of
/// them every minute regardless.
///
/// It ticks whether or not a label reads it: with nobody reading, a tick is one wakeup a minute
/// that redraws nothing, cheaper than every label holding the clock with a task of its own.
@MainActor @Observable
public final class DSMinuteClock {
    public static let shared = DSMinuteClock()

    /// The time at the last tick.
    public private(set) var now = Date.now

    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var visibilityObserver: (any NSObjectProtocol)?

    private init() {
        #if canImport(AppKit)
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followAppVisibility() }
        }
        #endif
        startTicking()
    }

    #if canImport(AppKit)
    private func followAppVisibility() {
        if NSApp.occlusionState.contains(.visible) {
            // Ages may have moved on while nothing showed them.
            now = .now
            startTicking()
        } else {
            ticking?.cancel()
            ticking = nil
        }
    }
    #endif

    private func startTicking() {
        guard ticking == nil else { return }
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                // On the minute, as `TimelineView(.everyMinute)` did, so every age moves at once.
                let fraction = Date.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(60 - fraction), tolerance: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.now = .now
            }
        }
    }
}
