import SwiftUI

/// The frame both home screens share: the lockup, anything urgent, the cards, a quiet link, then
/// anything else, in one centered column whose content fades in after the lockup.
///
/// The lockup sits 224pt from the top of the window, as the reference app places its wordmark, while
/// everything fits below it. Taller content pushes it up only as far as needed, and the page
/// scrolls once even that runs out.
struct HomePage<Notice: View, Cards: View, Footer: View, Content: View>: View {
    /// Whether there are tasks yet; the cards sit a little lower once there's work.
    var hasActivity = false
    /// What needs the user, above the cards so it's the first thing read after the lockup.
    @ViewBuilder var notice: Notice
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
                    notice
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
            .padding([.horizontal, .bottom], gutter)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.dsBackground)
        #if os(macOS)
        // The lockup names the window here; the toolbar repeating "Native" over it would stutter.
        .toolbar(removing: .title)
        #endif
        .onGeometryChange(for: Viewport.self) { proxy in
            Viewport(
                width: proxy.size.width,
                height: proxy.size.height + proxy.safeAreaInsets.top,
                safeAreaTop: proxy.safeAreaInsets.top
            )
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
        let roomAbove = viewport.height - contentHeight - gutter
        let fromWindowTop = min(HomeLayout.heroTop, max(gutter, roomAbove))
        return max(0, fromWindowTop - viewport.safeAreaTop)
    }

    private var gutter: CGFloat {
        viewport.width < HomeLayout.compactWidth ? HomeLayout.compactGutter : HomeLayout.gutter
    }
}

/// The page's size and how much of its top the toolbar covers.
private nonisolated struct Viewport: Equatable {
    /// Starts wide, so a page that hasn't been measured yet lays out as on a Mac.
    var width: CGFloat = .infinity
    var height: CGFloat = 0
    var safeAreaTop: CGFloat = 0
}
