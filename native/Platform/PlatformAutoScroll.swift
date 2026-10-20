#if (DEBUG || NATIVE_PERF) && os(macOS)
import AppKit

/// Scrolls the key window's tallest scroll view by itself, once per display frame, the way a
/// trackpad moves it: for measuring frame times with no accessibility client attached (one makes
/// SwiftUI update its accessibility tree every frame, which people without VoiceOver never pay
/// for). Debug builds on the Mac only, and Release builds compiled with `NATIVE_PERF`.
///
/// `-nativeAutoScroll <seconds>` waits that long after `start()`, scrolls down
/// `-nativeAutoScrollDistance` points (30,000; negative scrolls up, as from the bottom of a
/// transcript) at `-nativeAutoScrollSpeed` points a second (6,000) and back, then writes "done" to
/// `-nativeAutoScrollLog <path>`.
///
/// With `-nativeAutoScrollWheel YES` it scrolls the way a trackpad does instead: one continuous
/// scroll gesture of pixel-delta wheel events, sent through the window to whatever is under the
/// middle of the scroll view, so SwiftUI's own scrolling and any nested scroll views see them. Setting
/// the clip view's bounds directly leaves a SwiftUI scroll view with a bound `scrollPosition` (the
/// transcript) showing rows from before the scroll. The real pointer never moves.
@MainActor
final class PlatformAutoScroll: NSObject {
    private static var running: PlatformAutoScroll?

    private let scrollView: NSScrollView
    private let origin: CGFloat
    private let distance: CGFloat
    private let speed: CGFloat
    private let usesWheel: Bool
    private var started: CFTimeInterval?
    private var link: CADisplayLink?
    /// How far the last frame scrolled, and the part of a pixel wheel events haven't sent yet.
    private var lastOffset: CGFloat = 0
    private var remainder: CGFloat = 0

    /// Starts once per launch, when the launch arguments ask for it.
    static func startIfRequested() {
        let defaults = UserDefaults.standard
        let delay = defaults.double(forKey: "nativeAutoScroll")
        guard delay > 0, running == nil else { return }
        let distance = defaults.double(forKey: "nativeAutoScrollDistance")
        let speed = defaults.double(forKey: "nativeAutoScrollSpeed")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                let contentView = window.contentView,
                let scrollView = tallest(in: contentView)
            else { return }
            let scroll = PlatformAutoScroll(
                scrollView: scrollView, distance: distance != 0 ? distance : 30_000, speed: speed > 0 ? speed : 6_000,
                usesWheel: defaults.bool(forKey: "nativeAutoScrollWheel"))
            running = scroll
            scroll.begin()
        }
    }

    private init(scrollView: NSScrollView, distance: CGFloat, speed: CGFloat, usesWheel: Bool) {
        self.scrollView = scrollView
        origin = scrollView.contentView.bounds.origin.y
        self.distance = distance
        self.speed = speed
        self.usesWheel = usesWheel
    }

    private func begin() {
        let link = scrollView.displayLink(target: self, selector: #selector(step(_:)))
        // As fast as ProMotion goes, as a trackpad flick would drive it.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let start = started ?? now
        started = start
        let leg = abs(distance) / speed
        let t = now - start
        guard t < leg * 2 else {
            link.invalidate()
            if usesWheel { wheel(by: 0, phase: .ended) }
            finish()
            return
        }
        let offset = (t < leg ? t : 2 * leg - t) * speed * (distance < 0 ? -1 : 1)
        if usesWheel {
            wheel(by: offset - lastOffset, phase: t == 0 ? .began : .changed)
            lastOffset = offset
            return
        }
        let flip: CGFloat = scrollView.documentView?.isFlipped == false ? -1 : 1
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: origin + flip * offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Sends a wheel event moving the content `delta` points (positive scrolls further down the
    /// document) over the middle of the scroll view.
    private func wheel(by delta: CGFloat, phase: CGScrollPhase) {
        remainder += delta
        let pixels = remainder.rounded(.towardZero)
        remainder -= pixels
        guard let window = scrollView.window,
            let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-pixels), wheel2: 0,
                wheel3: 0)
        else { return }
        let middle = window.convertPoint(
            toScreen: scrollView.convert(NSPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY), to: nil))
        // Core Graphics counts screen coordinates from the top of the main display.
        event.location = CGPoint(x: middle.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - middle.y)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        if let wheel = NSEvent(cgEvent: event) {
            window.sendEvent(wheel)
        }
    }

    private func finish() {
        if let path = UserDefaults.standard.string(forKey: "nativeAutoScrollLog"), !path.isEmpty {
            FileManager.default.createFile(atPath: path, contents: Data("done\n".utf8))
        }
    }

    private static func tallest(in view: NSView) -> NSScrollView? {
        var best: NSScrollView?
        var stack = [view]
        while let next = stack.popLast() {
            if let scrollView = next as? NSScrollView,
                (scrollView.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0)
            {
                best = scrollView
            }
            stack.append(contentsOf: next.subviews)
        }
        return best
    }
}
#endif
