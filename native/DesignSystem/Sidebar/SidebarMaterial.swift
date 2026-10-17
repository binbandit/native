import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// What a translucent sidebar blurs.
public enum DSSidebarBlending: Sendable {
    /// The desktop behind the window (the system sidebar look).
    case behindWindow
    /// The window's own content (galleries, overlays).
    case withinWindow
}

extension View {
    /// The translucent sidebar backdrop. Use it only for a hand-built sidebar column; a
    /// `NavigationSplitView` sidebar already has the system's. Sidebar components draw nothing
    /// opaque, so it reads through everything. On the Mac `.behindWindow` is the system sidebar
    /// material; on iPadOS, and for `.withinWindow`, it's SwiftUI's thin material.
    public func dsSidebarBackground(blending: DSSidebarBlending = .behindWindow) -> some View {
        background {
            Group {
                #if canImport(AppKit)
                if blending == .behindWindow {
                    SidebarMaterial()
                } else {
                    // AppKit's within-window vibrancy can't see SwiftUI content drawn behind it in
                    // the same hosting view; SwiftUI's own material can.
                    Rectangle().fill(.thinMaterial)
                }
                #else
                Rectangle().fill(.thinMaterial)
                #endif
            }
            .ignoresSafeArea()
        }
    }
}

#if canImport(AppKit)
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
#endif
