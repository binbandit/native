import CoreFoundation
import Dispatch
import Observation

/// Whether the main window's first frame is on screen yet, for views that hold back what the
/// first frame can do without, so it comes sooner.
@MainActor
@Observable
final class FirstFrame {
    static let shared = FirstFrame()

    private(set) var isOnScreen = false
    @ObservationIgnored private var isWatching = false

    /// Call from the window's `onAppear`. The frame is on screen when the main run loop next goes
    /// to sleep, after Core Animation has committed it; `isOnScreen` turns on the turn after that,
    /// so what it brings in isn't counted in the launch milestones marked then.
    func watch() {
        guard !isOnScreen, !isWatching else { return }
        isWatching = true
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, .max) {
            _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { FirstFrame.shared.isOnScreen = true }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
