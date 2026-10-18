import SwiftUI

// How see-through the translucent layers are: the sidebar, overlays (popovers, toasts) and the
// floating controls' glass. One user preference, set once per window with `.dsTransparency(_:)`,
// and every translucent surface in the design system reads it; feature views never pick their own
// material. Content stays opaque at every level (glass is for the control layer only).

/// How much of what's behind the app shows through its translucent layers.
public nonisolated enum DSTransparency: String, CaseIterable, Identifiable, Sendable {
    /// Nothing shows through: what Reduce Transparency gives.
    case solid
    /// A hint of the desktop and the content behind.
    case subtle
    /// The system's own materials, as macOS and iPadOS draw them. The most see-through level:
    /// macOS tints its sidebar glass with the wallpaper rather than showing windows through it, and
    /// clear glass under text stops it reading, so there is nothing clearer worth offering.
    case standard

    public var id: Self { self }

    public var title: String {
        switch self {
        case .solid: "Solid"
        case .subtle: "Subtle"
        case .standard: "Standard"
        }
    }

    /// How much of the sidebar's own color covers the material behind it (1 is opaque; Standard
    /// leaves the system's material as it is).
    public var sidebarTint: Double {
        switch self {
        case .solid: 1
        case .subtle: 0.65
        case .standard: 0
        }
    }

    /// `sidebarTint` for a window's appearance. Dark mode's sidebar and chrome sit a step deeper
    /// than its content, darker than any system material, so the material shows through at most a
    /// fifth as much as the level says: a hint of the desktop rather than a gray that would rise above
    /// the content. True Black's are opaque, pure black, for OLED screens.
    public func sidebarTint(colorScheme: ColorScheme, darkTone: DSDarkTone) -> Double {
        guard colorScheme == .dark else { return sidebarTint }
        return darkTone == .trueBlack ? 1 : 1 - (1 - sidebarTint) * 0.2
    }

    /// How much of the overlay color covers the blur behind menus, popovers and toasts. Overlays
    /// hold text the user reads, so even Standard keeps them mostly opaque.
    public var overlayTint: Double {
        switch self {
        case .solid: 1
        case .subtle: 0.92
        case .standard: 0.8
        }
    }

    /// The glass behind floating controls (the composer, glass buttons), or nil when they sit on
    /// the opaque surface instead.
    public var controlGlass: Glass? {
        switch self {
        case .solid: nil
        case .subtle: .regular.tint(Color.dsSurface.opacity(0.6))
        case .standard: .regular
        }
    }
}

nonisolated extension EnvironmentValues {
    /// The transparency translucent surfaces draw at: the user's choice, or Solid while the system's
    /// Reduce Transparency setting is on. Set it with `.dsTransparency(_:)`.
    @Entry public var dsTransparency: DSTransparency = .standard
    /// Whether views draw on Liquid Glass (the floating composer, glass buttons). Set by
    /// `dsGlassEffect(in:)`; tokens that would blend into the glass resolve to their glass values.
    @Entry public var dsOnGlass = false
}

/// A color with its own value on Liquid Glass (`dsOnGlass`). Glass renders what's on it vibrantly,
/// so an opaque gray there takes on the glass's own shade: on an active window's lighter glass, the
/// composer's outline, rules and pill borders vanished. A translucent value keeps its contrast with
/// whatever shade the glass takes.
nonisolated struct DSGlassAwareStyle: ShapeStyle, Hashable {
    let base: Color
    let glass: Color

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        (environment.dsOnGlass ? glass : base).resolve(in: environment)
    }
}

extension View {
    /// Sets how see-through this window's translucent layers are. Put it on each window's root, next
    /// to `.dsAccentPalette(themeID:)`. Reduce Transparency always wins and forces Solid.
    public func dsTransparency(_ preference: DSTransparency) -> some View {
        modifier(DSTransparencyModifier(preference: preference))
    }
}

private struct DSTransparencyModifier: ViewModifier {
    let preference: DSTransparency

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.environment(\.dsTransparency, reduceTransparency ? .solid : preference)
    }
}
