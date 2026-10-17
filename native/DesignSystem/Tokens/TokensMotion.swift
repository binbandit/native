import SwiftUI

// Motion tokens. the reference app keeps motion short and functional: hover highlights appear instantly and
// fade out over 100ms, panels slide over 180ms ease-out. the reference app's default is Tailwind's 150ms
// cubic-bezier(.4, 0, .2, 1). Animated components respect Reduce Motion themselves.

extension Animation {
    /// Hover highlights fading out (the reference app: `transition: none` in, 100ms ease-out out).
    public nonisolated static let dsHoverOut = Animation.easeOut(duration: 0.1)
    /// Color and opacity changes on controls (the reference app `--core-v2-motion-duration` 100ms ease-out).
    public nonisolated static let dsQuick = Animation.easeOut(duration: 0.1)
    /// State changes (the reference app/Tailwind default: 150ms, cubic-bezier(.4, 0, .2, 1)).
    public nonisolated static let dsStandard = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.15)
    /// Sidebars and panes sliding (the reference app `PANEL_TRANSITION_DURATION` 180ms ease-out).
    public nonisolated static let dsPanel = Animation.easeOut(duration: 0.18)
    /// Menus and popovers appearing (the reference app: opacity + scale 95%, 100ms).
    public nonisolated static let dsPopover = Animation.easeOut(duration: 0.1)
    /// Disclosure: rows expanding and collapsing.
    public nonisolated static let dsDisclosure = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.18)
}

extension View {
    /// Tracks hover the way the reference app does: highlights appear instantly and fade out over 100ms.
    public func trackHover(_ isHovered: Binding<Bool>) -> some View {
        onHover { hovering in
            withAnimation(hovering ? nil : .dsHoverOut) {
                isHovered.wrappedValue = hovering
            }
        }
    }
}
