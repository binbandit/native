import SwiftUI

@testable import Native

@main
@MainActor
private struct ReadingPositionRegression {
    private static var failures = 0

    static func main() {
        let tracker = SessionTranscriptPlaceTracker()
        tracker.viewport = viewport(y: 300)
        tracker.layoutChanged()
        expect(isKept(tracker), "Wait for row geometry before recording a passage")

        tracker.lineFrames["reading"] = CGRect(x: 0, y: 350, width: 500, height: 80)
        tracker.lineChanged("reading")
        let passage = SessionTranscriptPlace(lineID: "reading", anchor: UnitPoint(x: 0.5, y: 50.0 / 320))
        expect(remembers(tracker, passage), "Record a row that arrives after the viewport")

        // SwiftUI may remove the child rows before the transcript's onDisappear saves its place.
        tracker.lineFrames.removeAll()
        expect(remembers(tracker, passage), "Child teardown must preserve the passage")
        tracker.layoutChanged()
        expect(remembers(tracker, passage), "A layout without rows must preserve the passage")
        tracker.viewport = nil
        tracker.layoutChanged()
        expect(remembers(tracker, passage), "A missing viewport must preserve the passage")
        tracker.viewport = SessionTranscriptViewport(bounds: .zero, contentHeight: 0)
        tracker.layoutChanged()
        expect(remembers(tracker, passage), "A zero-sized layout must preserve the passage")

        tracker.viewport = viewport(y: 800)
        tracker.layoutChanged()
        expect(remembers(tracker, nil), "A measured bottom must follow the latest output")

        tracker.lineFrames["latest"] = CGRect(x: 0, y: 1100, width: 500, height: 80)
        tracker.viewport = viewport(y: 799)
        tracker.layoutChanged()
        let nearBottom = SessionTranscriptPlace(lineID: "latest", anchor: UnitPoint(x: 0.5, y: 301.0 / 320))
        expect(remembers(tracker, nearBottom), "Even a one-point scroll above the bottom is reading")

        if failures > 0 { exit(1) }
        print("PASS: transcript teardown, incomplete layouts, late rows and bottom-follow state")
    }

    private static func viewport(y: CGFloat) -> SessionTranscriptViewport {
        SessionTranscriptViewport(bounds: CGRect(x: 0, y: y, width: 500, height: 400), contentHeight: 1200)
    }

    private static func remembers(_ tracker: SessionTranscriptPlaceTracker, _ place: SessionTranscriptPlace?) -> Bool {
        guard case .remember(let actual) = tracker.leaving else { return false }
        return actual == place
    }

    private static func isKept(_ tracker: SessionTranscriptPlaceTracker) -> Bool {
        if case .keep = tracker.leaving { return true }
        return false
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            print("FAIL: \(message)")
            failures += 1
        }
    }
}
