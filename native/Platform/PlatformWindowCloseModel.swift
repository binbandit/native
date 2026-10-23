#if os(macOS)
import AppKit
import Observation

/// File > Close follows AppKit's front window, including panels outside the SwiftUI scene.
@MainActor
@Observable
final class PlatformWindowCloseModel: NSObject {
    private(set) var canClose = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(update), name: NSApplication.didUpdateNotification, object: nil)
        update()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func close() {
        guard let window = frontWindow else { return }
        close(window)
        update()
    }

    func closeAll() {
        for window in frontWindows where window.sheetParent == nil {
            close(window)
        }
        update()
    }

    private func close(_ window: NSWindow) {
        var window = window
        while let sheet = window.attachedSheet {
            window = sheet
        }
        if window.isSheet {
            // Use SwiftUI's cancellation path so the presentation binding follows the dismissal.
            _ = window.contentView?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: nil)
        } else {
            window.performClose(nil)
        }
    }

    private var frontWindow: NSWindow? {
        frontWindows.first
    }

    private var frontWindows: [NSWindow] {
        // orderedWindows excludes panels. The Window Server's order includes About and Quick
        // Look, even when the main window remains key behind them. No other app's windows enter
        // this list, and menu/tooltip windows cannot become key and have no close button.
        (NSWindow.windowNumbers(options: []) ?? [])
            .compactMap { NSApp.window(withWindowNumber: $0.intValue) }
            .filter { $0.isVisible && ($0.canBecomeKey || $0.isSheet || $0.styleMask.contains(.closable)) }
    }

    @objc private func update() {
        // Enabling the menu needs no Window Server query on every event. Resolve order only
        // when the user actually closes something.
        let hasWindow = NSApp.windows.contains { $0.isVisible && ($0.isSheet || $0.styleMask.contains(.closable)) }
        if canClose != hasWindow { canClose = hasWindow }
    }
}
#endif
