import Foundation
import os

#if canImport(AppKit)
import AppKit
import QuartzCore

/// How steadily the main thread keeps up with the display, for measuring scrolling and animation
/// (`docs/performance.md`, "Frame pacing"). Off unless the app is launched with `-framePacing YES`.
///
/// A display link fires on the main run loop once per display refresh (every 8.3 ms at 120 Hz), so
/// a refresh it missed is a frame the main thread was too busy to produce. Once a second it logs
/// `frames <fired>/<refreshes>, dropped <n>, late <n>, worst <ms> ms` under `Native`/`Frames`: of the
/// display's refreshes that second, how many the main thread missed (`dropped`), in how many stalls
/// (`late`), and the longest stall. Unlike an Instruments recording, it costs next to nothing and
/// writes nothing to disk.
@MainActor
final class FramePacing: NSObject {
    private static var shared: FramePacing?
    private let logger = Logger(subsystem: "Native", category: "Frames")
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private var second = Second()

    private struct Second {
        var start: CFTimeInterval = 0
        var fired = 0
        var refreshes = 0
        var dropped = 0
        var late = 0
        var worst: CFTimeInterval = 0
    }

    /// Starts the probe when the `framePacing` default is on.
    static func startIfRequested() {
        guard shared == nil, UserDefaults.standard.bool(forKey: "framePacing"), let screen = NSScreen.main else {
            return
        }
        let pacing = FramePacing()
        let link = screen.displayLink(target: pacing, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        pacing.link = link
        shared = pacing
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let period = max(link.targetTimestamp - link.timestamp, 1.0 / 240)
        defer { last = now }
        guard let last else {
            second.start = now
            return
        }
        let interval = now - last
        let refreshes = max(Int((interval / period).rounded()), 1)
        second.fired += 1
        second.refreshes += refreshes
        second.dropped += refreshes - 1
        if refreshes > 1 { second.late += 1 }
        second.worst = max(second.worst, interval)
        guard now - second.start >= 1 else { return }
        logger.notice(
            "frames \(self.second.fired)/\(self.second.refreshes), dropped \(self.second.dropped), late \(self.second.late), worst \(Int(self.second.worst * 1000)) ms"
        )
        second = Second(start: now)
    }
}
#else
@MainActor
enum FramePacing {
    static func startIfRequested() {}
}
#endif
