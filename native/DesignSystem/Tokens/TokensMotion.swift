import SwiftUI

// Motion tokens. Motion stays short and functional: hover highlights appear instantly and fade out
// over 100ms, state changes take 150ms, and panels slide over 180ms ease-out. Animated components
// respect Reduce Motion themselves.

extension Animation {
    /// Hover highlights fading out (they appear instantly).
    public nonisolated static let dsHoverOut = Animation.easeOut(duration: 0.1)
    /// Color and opacity changes on controls.
    public nonisolated static let dsQuick = Animation.easeOut(duration: 0.1)
    /// State changes.
    public nonisolated static let dsStandard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.15)
    /// Sidebars and panes sliding.
    public nonisolated static let dsPanel = Animation.easeOut(duration: 0.18)
    /// Menus and popovers appearing.
    public nonisolated static let dsPopover = Animation.easeOut(duration: 0.1)
    /// Disclosure: rows expanding and collapsing.
    public nonisolated static let dsDisclosure = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.18)
}

extension View {
    /// Tracks hover: highlights appear instantly and fade out over 100ms, so the pointer feels direct.
    /// On iPadOS the pointer drives the same hover, so the system's own pointer highlight is turned
    /// off to keep one treatment; touch uses the components' pressed states.
    public func trackHover(_ isHovered: Binding<Bool>) -> some View {
        onHover { hovering in
            withAnimation(hovering ? nil : .dsHoverOut) {
                isHovered.wrappedValue = hovering
            }
        }
        #if os(iOS)
        .hoverEffectDisabled()
        #endif
    }
}
