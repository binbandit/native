import AppKit
import SwiftUI

extension View {
    /// The translucent sidebar backdrop: the system sidebar material, blurring the desktop behind
    /// the window. Use it only for a hand-built sidebar column; a `NavigationSplitView` sidebar
    /// already has it. Sidebar components draw nothing opaque, so it reads through everything.
    /// Pass `.withinWindow` to blur the window's own content instead (galleries, overlays).
    public func dsSidebarBackground(blending: NSVisualEffectView.BlendingMode = .behindWindow) -> some View {
        background {
            if blending == .behindWindow {
                SidebarMaterial()
                    .ignoresSafeArea()
            } else {
                // AppKit's within-window vibrancy can't see SwiftUI content drawn behind it in the
                // same hosting view; SwiftUI's own material can.
                Rectangle()
                    .fill(.thinMaterial)
                    .ignoresSafeArea()
            }
        }
    }
}

/// `NSVisualEffectView` with the `.sidebar` material behind the window, following the window's
/// active state and the SwiftUI color scheme (so forced-appearance subtrees tint correctly).
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
    }
}
