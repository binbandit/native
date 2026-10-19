#if DEBUG
import SwiftUI

/// Scrolls Files Changed by itself, for measuring frame times without an accessibility client
/// attached (one makes SwiftUI update its accessibility tree every frame, which users without
/// VoiceOver never pay for). Debug builds only: `-gitHubAutoScroll <seconds>` waits that long after
/// the list appears, scrolls down `-gitHubAutoScrollDistance` points (30,000) at
/// `-gitHubAutoScrollSpeed` points a second (6,000) and back up, then appends "done" to
/// `-gitHubAutoScrollLog <path>`.
struct PullRequestFilesAutoScroll: ViewModifier {
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        let delay = UserDefaults.standard.double(forKey: "gitHubAutoScroll")
        if delay > 0 {
            content
                .scrollPosition($position)
                .task { await drive(after: delay) }
        } else {
            content
        }
    }

    private func drive(after delay: Double) async {
        try? await Task.sleep(for: .seconds(delay))
        let defaults = UserDefaults.standard
        let distance = Self.value(defaults.double(forKey: "gitHubAutoScrollDistance"), or: 30_000)
        let speed = Self.value(defaults.double(forKey: "gitHubAutoScrollSpeed"), or: 6_000)
        let leg = distance / speed
        let start = ContinuousClock.now
        while !Task.isCancelled {
            let elapsed = start.duration(to: .now)
            let t = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            guard t < leg * 2 else { break }
            position.scrollTo(y: (t < leg ? t : 2 * leg - t) * speed)
            // Faster than the display, so every frame has a new offset; time decides where.
            try? await Task.sleep(for: .milliseconds(4))
        }
        if let path = defaults.string(forKey: "gitHubAutoScrollLog"), !path.isEmpty {
            FileManager.default.createFile(atPath: path, contents: Data("done\n".utf8))
        }
    }

    private static func value(_ stored: Double, or fallback: Double) -> Double {
        stored > 0 ? stored : fallback
    }
}
#endif
