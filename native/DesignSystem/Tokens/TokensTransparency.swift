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
    /// The system's own materials, as macOS and iPadOS draw them.
    case standard
    /// Lighter glass and overlays, for calm wallpapers.
    case clear

    public var id: Self { self }

    public var title: String {
        switch self {
        case .solid: "Solid"
        case .subtle: "Subtle"
        case .standard: "Standard"
        case .clear: "Clear"
        }
    }

    /// How much of the sidebar's own color covers the material behind it (1 is opaque). Standard
    /// and Clear leave the system's material as it is; Clear also makes its glass clear.
    public var sidebarTint: Double {
        switch self {
        case .solid: 1
        case .subtle: 0.65
        case .standard, .clear: 0
        }
    }

    /// How much of the overlay color covers the blur behind menus, popovers and toasts. Overlays
    /// hold text the user reads, so they stay mostly opaque even at Clear.
    public var overlayTint: Double {
        switch self {
        case .solid: 1
        case .subtle: 0.94
        case .standard: 0.84
        case .clear: 0.66
        }
    }

    /// The glass behind floating controls (the composer, glass buttons), or nil when they sit on
    /// the opaque surface instead.
    public var controlGlass: Glass? {
        switch self {
        case .solid: nil
        case .subtle: .regular.tint(Color.dsSurface.opacity(0.6))
        case .standard: .regular
        case .clear: .clear
        }
    }
}

extension EnvironmentValues {
    /// The transparency translucent surfaces draw at: the user's choice, or Solid while the system's
    /// Reduce Transparency setting is on. Set it with `.dsTransparency(_:)`.
    @Entry public var dsTransparency: DSTransparency = .standard
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
