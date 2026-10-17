#if os(macOS)
import AppKit
import SwiftUI

/// Hosts a tab's terminal view. The view belongs to the tab, not to SwiftUI: it's moved into this
/// container while the tab shows and out again when it doesn't, so its shell and scrollback
/// survive tab switches, the panel hiding and other tasks being selected.
struct TerminalSurfaceHost: NSViewRepresentable {
    let surface: TerminalSurface

    func makeNSView(context: Context) -> TerminalSurfaceContainer {
        TerminalSurfaceContainer()
    }

    func updateNSView(_ container: TerminalSurfaceContainer, context: Context) {
        container.host(surface as? NSView)
    }

    static func dismantleNSView(_ container: TerminalSurfaceContainer, coordinator: ()) {
        container.host(nil)
    }
}

final class TerminalSurfaceContainer: NSView {
    /// Shows `view` filling the container, in place of whatever it showed before.
    func host(_ view: NSView?) {
        guard subviews.first !== view else { return }
        subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        view.removeFromSuperview()
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}
#endif
