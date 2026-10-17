import SwiftUI

/// The frame both home screens share: the lockup, the cards under it, a quiet link, then anything
/// else, in one centered column whose content fades in after the lockup.
///
/// The lockup sits 224pt from the top of the window, as Conductor places its wordmark, while
/// everything fits below it. Taller content pushes it up only as far as needed, and the page
/// scrolls once even that runs out.
struct HomePage<Cards: View, Footer: View, Content: View>: View {
    /// Whether there are tasks yet; the cards sit a little lower once there's work.
    var hasActivity = false
    @ViewBuilder var cards: Cards
    @ViewBuilder var footer: Footer
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewport = Viewport()
    @State private var contentHeight: CGFloat = 0
    @State private var isShown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HomeHero()
                VStack(spacing: 0) {
                    HomeCardGrid {
                        cards
                    }
                    footer
                        .padding(.top, HomeLayout.footerSpacing)
                    content
                }
                .padding(.top, HomeLayout.heroSpacingBelow + (hasActivity ? HomeLayout.activitySpacing : 0))
                .opacity(isShown ? 1 : 0)
            }
            .frame(maxWidth: HomeLayout.columnWidth)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                contentHeight = $0
            }
            .padding(.top, topPadding)
            .padding([.horizontal, .bottom], HomeLayout.gutter)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.dsBackground)
        .onGeometryChange(for: Viewport.self) { proxy in
            Viewport(height: proxy.size.height + proxy.safeAreaInsets.top, safeAreaTop: proxy.safeAreaInsets.top)
        } action: {
            viewport = $0
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : HomeLayout.contentFadeIn) {
                isShown = true
            }
        }
    }

    /// The space above the lockup, measured from the top of the scroll view's content, which
    /// starts under the toolbar.
    private var topPadding: CGFloat {
        let roomAbove = viewport.height - contentHeight - HomeLayout.gutter
        let fromWindowTop = min(HomeLayout.heroTop, max(HomeLayout.gutter, roomAbove))
        return max(0, fromWindowTop - viewport.safeAreaTop)
    }
}

/// The window's height and how much of its top the toolbar covers.
private nonisolated struct Viewport: Equatable {
    var height: CGFloat = 0
    var safeAreaTop: CGFloat = 0
}
