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
    /// system draws: lower levels lay the solid sidebar color over it.
    public func dsSidebarColumnTransparency() -> some View {
        modifier(SidebarColumnTransparency())
    }
}

private struct SidebarBackdrop: View {
    let blending: DSSidebarBlending

    @Environment(\.dsTransparency) private var transparency
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tint = transparency.sidebarTint(colorScheme: colorScheme, darkTone: darkTone)
        ZStack {
            if tint < 1 {
                material
            }
            Rectangle()
                .fill(.dsSidebarSolid)
                .opacity(tint)
        }
    }

    @ViewBuilder private var material: some View {
        #if canImport(AppKit)
        if blending == .behindWindow {
            DSBehindWindowMaterial()
        } else {
            // AppKit's within-window vibrancy can't see SwiftUI content drawn behind it in the
            // same hosting view; SwiftUI's own material can.
            Rectangle().fill(.thinMaterial)
        }
        #else
        Rectangle().fill(.thinMaterial)
        #endif
    }
}

private struct SidebarColumnTransparency: ViewModifier {
    @Environment(\.dsTransparency) private var transparency
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.colorScheme) private var colorScheme

    /// The system's light sidebar is a cool gray; on Wool a little of Wool's own sidebar color
    /// keeps it from reading cold beside the warm content.
    private static let woolWarmth = 0.4

    private var tint: Double {
        let tint = transparency.sidebarTint(colorScheme: colorScheme, darkTone: darkTone)
        let isWool = colorScheme == .light && lightTone == .wool
        return isWool ? max(tint, Self.woolWarmth) : tint
    }

    func body(content: Content) -> some View {
        content
            .background {
                Rectangle()
                    .fill(.dsSidebarSolid)
                    .opacity(tint)
                    .ignoresSafeArea()
                    .animation(.dsStandard, value: tint)
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
#endif
