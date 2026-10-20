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

extension EnvironmentValues {
    /// Whether the page draws `dsToolbarBand`, so a scroll view in it that picks its own top edge
    /// effect leaves the effect hidden.
    @Entry public var dsDrawsToolbarBand = false
}

#if os(macOS)
private struct DSToolbarBand: ViewModifier {
    let showsDivider: Bool
    /// Where the page starts in the window, under the toolbar (and any bar under it): the band
    /// reaches from the top of the window down to there.
    @State private var pageTop: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Neither the toolbar's own background nor the edge effect: inactive windows draw both
            // solid, in the system's colors, and the edge effect blurs rows into the title bar.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .scrollEdgeEffectHidden(true, for: .top)
            .environment(\.dsDrawsToolbarBand, true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { top in
                pageTop = top
            }
            .overlay {
                // Reaching up over the safe area, which a proxy there no longer reports as an inset.
                GeometryReader { proxy in
                    let height = max(0, pageTop - proxy.frame(in: .global).minY)
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
