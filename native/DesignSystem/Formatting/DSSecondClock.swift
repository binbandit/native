import Foundation
import Observation

#if canImport(AppKit)
import AppKit
#endif

/// One clock for every label that counts seconds (`ElapsedTimeText`): it ticks once a second while
/// any of them is on screen and the app is visible, and not at all otherwise. Reading `now` in a
/// view's body redraws only that view on each tick, so a dozen running clocks cost one wakeup a
/// second, not one each, and nothing re-renders the window per frame.
@MainActor @Observable
public final class DSSecondClock {
    public static let shared = DSSecondClock()

    /// The time at the last tick.
    public private(set) var now = Date.now

    @ObservationIgnored private var holders = 0
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var isAppVisible = true
    @ObservationIgnored private var visibilityObserver: (any NSObjectProtocol)?

    private init() {
        #if canImport(AppKit)
        visibilityObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followAppVisibility() }
        }
        #endif
    }

    /// Keeps the clock ticking until the calling task is cancelled: run it from the counting view's
    /// `.task`, which SwiftUI cancels when the view goes away.
    public func hold() async {
        holders += 1
        now = .now
        update()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        holders -= 1
        update()
    }

    #if canImport(AppKit)
    private func followAppVisibility() {
        isAppVisible = NSApp.occlusionState.contains(.visible)
        if isAppVisible { now = .now }
        update()
    }
    #endif

    private func update() {
        let shouldTick = holders > 0 && isAppVisible
        if shouldTick, ticking == nil {
            ticking = Task { [weak self] in
                while !Task.isCancelled {
                    // On the second boundary, so labels that started together change together.
                    let fraction = Date.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                    try? await Task.sleep(for: .seconds(1 - fraction), tolerance: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    self?.now = .now
                }
            }
        } else if !shouldTick, let ticking {
            ticking.cancel()
            self.ticking = nil
        }
    }
}
