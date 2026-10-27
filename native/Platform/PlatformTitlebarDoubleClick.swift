import SwiftUI

extension View {
    /// SwiftUI's custom toolbar does not reliably deliver empty-space double-clicks to AppKit.
    func platformTitlebarDoubleClick() -> some View {
        #if os(macOS)
        background(PlatformTitlebarDoubleClickReader())
        #else
        self
        #endif
    }
}

#if os(macOS)
import AppKit

private struct PlatformTitlebarDoubleClickReader: NSViewRepresentable {
    func makeNSView(context: Context) -> PlatformTitlebarDoubleClickView { PlatformTitlebarDoubleClickView() }
    func updateNSView(_ view: PlatformTitlebarDoubleClickView, context: Context) {}
    static func dismantleNSView(_ view: PlatformTitlebarDoubleClickView, coordinator: ()) { view.stop() }
}

private final class PlatformTitlebarDoubleClickView: NSView {
    private var monitor: Any?
    private var filledFrame: NSRect?
    private var frameBeforeFill: NSRect?
    private var consumesMouseUp = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        if event.type == .leftMouseUp {
            let consumed = consumesMouseUp
            consumesMouseUp = false
            return consumed
        }
        consumesMouseUp = false
        guard event.clickCount == 2, !event.modifierFlags.contains(.control),
            window.styleMask.contains(.titled), !window.styleMask.contains(.fullScreen),
            window.attachedSheet == nil,
            Self.isBackground(event.locationInWindow, in: window)
        else { return false }

        consumesMouseUp = true
        // Read on each click so a Desktop & Dock change takes effect without relaunching.
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case nil, "Maximize", "Zoom":
            window.performZoom(nil)
        case "Minimize":
            window.miniaturize(nil)
        case "Fill":
            toggleFill(window)
        default:
            break
        }
        // AppKit must not perform the same action a second time after our forwarding.
        return true
    }

    private static func isBackground(_ point: NSPoint, in window: NSWindow) -> Bool {
        guard point.y >= window.contentLayoutRect.maxY,
            let frameView = window.contentView?.superview,
            frameView.bounds.contains(frameView.convert(point, from: nil)),
            let hit = frameView.hitTest(frameView.convert(point, from: nil)), hit.mouseDownCanMoveWindow
        else { return false }

        // SwiftUI toolbar controls are hosted views, not NSControls. Exclude each whole item,
        // including its padding, while allowing the system's flexible and fixed spacers.
        for item in window.toolbar?.visibleItems ?? [] {
            guard item.itemIdentifier != .space, item.itemIdentifier != .flexibleSpace,
                let view = item.view, view.window === window, !view.isHidden
            else { continue }
            if view.bounds.contains(view.convert(point, from: nil)) { return false }
        }
        // The system title is not necessarily an NSToolbarItem. Its container can span all empty
        // space, so exclude the actual text and controls rather than the container's entire width.
        return !containsControl(at: point, in: frameView)
    }

    private static func containsControl(at point: NSPoint, in view: NSView) -> Bool {
        guard !view.isHidden, view.alphaValue > 0 else { return false }
        if view is NSControl, view.bounds.contains(view.convert(point, from: nil)) { return true }
        return view.subviews.contains { containsControl(at: point, in: $0) }
    }

    private func toggleFill(_ window: NSWindow) {
        if let filledFrame, let frameBeforeFill, window.frame == filledFrame {
            window.setFrame(frameBeforeFill, display: true)
            self.filledFrame = nil
            self.frameBeforeFill = nil
        } else if let screen = window.screen {
            frameBeforeFill = window.frame
            var frame = screen.visibleFrame
            frame.size.width = min(max(frame.width, window.minSize.width), window.maxSize.width)
            frame.size.height = min(max(frame.height, window.minSize.height), window.maxSize.height)
            window.setFrame(frame, display: true)
            filledFrame = window.frame
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        filledFrame = nil
        frameBeforeFill = nil
        consumesMouseUp = false
    }
}
#endif
