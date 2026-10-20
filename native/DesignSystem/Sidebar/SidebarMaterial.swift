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
    @Environment(\.sidebarColumnTint) private var tint

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

/// A split-view sidebar column's look, for chrome that continues the column past its edge (the
/// status bar), so the two read as one surface: the system's sidebar glass as it renders, under
/// the solid sidebar color at the column's tint.
struct SidebarColumnBackdrop: View {
    @Environment(\.sidebarColumnTint) private var tint

    var body: some View {
        ZStack {
            if tint < 1 {
                SidebarColumnGlass()
            }
            Rectangle()
                .fill(.dsSidebarSolid)
                .opacity(tint)
        }
        .animation(.dsStandard, value: tint)
    }
}

/// What the system's split-view sidebar glass renders, drawn where that glass can't be: macOS draws
/// the column with a private sidebar variant of `NSGlassEffectView`, and a public one renders as a
/// lit pane instead. Measured against the column on macOS 27 (pixel-identical in both appearances,
/// window active and inactive): in dark mode the glass is all but clear over the window's
/// background, the content-background material with the wallpaper's tint; in light mode it's
/// SwiftUI's thin material while the window is active and ultra-thin while it isn't.
private struct SidebarColumnGlass: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        #if canImport(AppKit)
        if colorScheme == .dark {
            DSBehindWindowMaterial(material: .contentBackground)
        } else {
            Rectangle().fill(appearsActive ? .thinMaterial : .ultraThinMaterial)
        }
        #else
        Rectangle().fill(.ultraThinMaterial)
        #endif
    }
}

nonisolated extension EnvironmentValues {
    /// How much of the solid sidebar color covers a split-view sidebar column's glass: the user's
    /// transparency for this appearance, except on Wool. The system's light sidebar is a cool gray
    /// that reads cold beside Wool's warm content, and the glass draws any warm tint inside it at
    /// close to full strength in an active window, so a Wool column is solid Wool at every level;
    /// that way chrome beside it (the status bar) can match it exactly.
    fileprivate var sidebarColumnTint: Double {
        let isWool = colorScheme == .light && dsLightTone == .wool
        return isWool ? 1 : dsTransparency.sidebarTint(colorScheme: colorScheme, darkTone: dsDarkTone)
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
