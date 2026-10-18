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
    /// `NavigationSplitView` sidebar already has the system's (give it
    /// `.dsSidebarColumnTransparency()`). Sidebar components draw nothing opaque, so it reads
    /// through everything. On the Mac `.behindWindow` is the system sidebar material; on iPadOS,
    /// and for `.withinWindow`, it's SwiftUI's thin material. Follows `\.dsTransparency`.
    public func dsSidebarBackground(blending: DSSidebarBlending = .behindWindow) -> some View {
        background {
            SidebarBackdrop(blending: blending)
                .ignoresSafeArea()
        }
    }

    /// Applies the user's transparency to a `NavigationSplitView` sidebar column, whose material the
    /// system draws: lower levels lay the solid sidebar color over it, and Clear asks the Mac's
    /// sidebar glass for its clear style.
    public func dsSidebarColumnTransparency() -> some View {
        modifier(SidebarColumnTransparency())
    }
}

private struct SidebarBackdrop: View {
    let blending: DSSidebarBlending

    @Environment(\.dsTransparency) private var transparency

    var body: some View {
        ZStack {
            if transparency != .solid {
                material
            }
            Rectangle()
                .fill(.dsSidebarSolid)
                .opacity(transparency.sidebarTint)
        }
    }

    @ViewBuilder private var material: some View {
        #if canImport(AppKit)
        if blending == .behindWindow {
            DSBehindWindowMaterial(material: transparency == .clear ? .fullScreenUI : .sidebar)
        } else {
            // AppKit's within-window vibrancy can't see SwiftUI content drawn behind it in the
            // same hosting view; SwiftUI's own material can.
            Rectangle().fill(transparency == .clear ? .ultraThinMaterial : .thinMaterial)
        }
        #else
        Rectangle().fill(transparency == .clear ? .ultraThinMaterial : .thinMaterial)
        #endif
    }
}

private struct SidebarColumnTransparency: ViewModifier {
    @Environment(\.dsTransparency) private var transparency

    func body(content: Content) -> some View {
        content
            .background {
                Rectangle()
                    .fill(.dsSidebarSolid)
                    .opacity(transparency.sidebarTint)
                    .ignoresSafeArea()
                    .animation(.dsStandard, value: transparency)
                #if canImport(AppKit)
                SidebarGlassStyle(isClear: transparency == .clear)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                #endif
            }
    }
}

#if canImport(AppKit)
/// An `NSVisualEffectView` blending what's behind the window, following the window's active state
/// and the SwiftUI color scheme (so forced-appearance subtrees tint correctly).
struct DSBehindWindowMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
    }
}

/// Sets the style of the `NSGlassEffectView` that macOS wraps a split view's sidebar in. SwiftUI
/// has no API for it, so this finds the glass among its ancestors; if a later macOS draws the
/// sidebar differently, nothing is found and Clear looks like Standard.
private struct SidebarGlassStyle: NSViewRepresentable {
    let isClear: Bool

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.style = isClear ? .clear : .regular
    }

    final class Probe: NSView {
        var style = NSGlassEffectView.Style.regular {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            var ancestor = superview
            while let view = ancestor, !(view is NSGlassEffectView) {
                ancestor = view.superview
            }
            guard let glass = ancestor as? NSGlassEffectView, glass.style != style else { return }
            glass.style = style
        }
    }
}
#endif
