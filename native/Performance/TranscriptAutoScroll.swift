#if DEBUG || NATIVE_PERF
import ACP
import SwiftUI

/// Scrolls a transcript through SwiftUI itself, for measuring rows coming into view
/// (docs/performance.md, "Long transcripts"). Scrolling its window's scroll view from outside
/// (`PlatformAutoScroll`) doesn't reach a bottom-anchored SwiftUI scroll view the way a trackpad does:
/// the rows slide off the end and nothing new is drawn.
///
/// `-nativeTranscriptAutoScroll <seconds>` waits that long after the transcript of the session
/// `-nativeOpenSession` names appears, then shows its prompts and replies one after another, newest
/// first, `-nativeTranscriptAutoScrollRate` a second (60), for `-nativeTranscriptAutoScrollCount` of
/// them (all), and back down to the latest. It writes "done" to `-nativeAutoScrollLog <path>` at the
/// end. Debug builds, and Release builds compiled with `NATIVE_PERF`.
@MainActor
enum TranscriptAutoScroll {
    private static var hasRun = false

    static func runIfRequested(session: SessionModel, proxy: ScrollViewProxy) async {
        let defaults = UserDefaults.standard
        let delay = defaults.double(forKey: "nativeTranscriptAutoScroll")
        // Only the session `-nativeOpenSession` opened, not one shown on the way there.
        let target = defaults.string(forKey: "nativeOpenSession")?.split(separator: "/").last.map(String.init)
        guard delay > 0, !hasRun, target == nil || target == session.id.rawValue else { return }
        hasRun = true
        try? await Task.sleep(for: .seconds(delay))
        let messages = session.state.items.compactMap { item -> String? in
            if case .message(let message) = item, message.role != .thought { item.id } else { nil }
        }
        let count = defaults.integer(forKey: "nativeTranscriptAutoScrollCount")
        let upward = Array(messages.reversed().prefix(count > 0 ? count : messages.count))
        let rate = defaults.double(forKey: "nativeTranscriptAutoScrollRate")
        let interval = Duration.seconds(1 / (rate > 0 ? rate : 60))
        let clock = ContinuousClock()
        var next = clock.now
        for id in upward + upward.reversed() {
            proxy.scrollTo(id, anchor: .top)
            next += interval
            try? await Task.sleep(until: next, clock: clock)
        }
        if let path = defaults.string(forKey: "nativeAutoScrollLog"), !path.isEmpty {
            FileManager.default.createFile(atPath: path, contents: Data("done\n".utf8))
        }
    }
}
#endif
