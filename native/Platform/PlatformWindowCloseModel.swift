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
        for window in NSApp.orderedWindows where window.isVisible && window.canBecomeKey && window.sheetParent == nil {
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
        // The main window may sit behind an About or Quick Look panel. Never fall back to it
        // while another visible window is in front, including when an AX command invokes Close.
        NSApp.keyWindow ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.canBecomeKey })
    }

    @objc private func update() {
        canClose =
            frontWindow.map { $0.isSheet || $0.attachedSheet != nil || $0.styleMask.contains(.closable) } ?? false
    }
}
#endif
