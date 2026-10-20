import SwiftUI

extension View {
    /// For a page under the window toolbar: what scrolls up under the toolbar passes behind a band
    /// of the design system's background, with a hairline under it, in place of the system's top
    /// scroll edge effect. That effect draws in the system's own colors, not the user's light or
    /// dark tone, and inactive windows show it as a solid band. Put it on the page itself, inside
    /// any bar under the toolbar (the band reaches down past the bar), not on a view that ignores
    /// the top safe area. iPadOS keeps the system's effect.
    ///
    /// The band is the page's own color, so only its hairline shows: pass whether anything has
    /// scrolled under it, or leave it showing for a page whose toolbar always closes off a title.
    public func dsToolbarBand(showsDivider: Bool = true) -> some View {
        #if os(macOS)
        modifier(DSToolbarBand(showsDivider: showsDivider))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct DSToolbarBand: ViewModifier {
    let showsDivider: Bool

    func body(content: Content) -> some View {
        content
            // Neither the toolbar's own background nor the edge effect: inactive windows draw both
            // solid, in the system's colors, and the edge effect blurs rows into the title bar.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .scrollEdgeEffectHidden(true, for: .top)
            .overlay {
                // Laid out over the safe area too, where the proxy says how far down it reaches.
                GeometryReader { proxy in
                    let height = proxy.safeAreaInsets.top
                    Rectangle()
                        .fill(.dsBackground)
                        .frame(height: height)
                        .overlay(alignment: .bottom) {
                            SeparatorLine()
                                .opacity(showsDivider ? 1 : 0)
                        }
                        .opacity(height > 0 ? 1 : 0)
                }
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
#endif
