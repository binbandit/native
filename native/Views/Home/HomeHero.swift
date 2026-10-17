import SwiftUI

/// Native's lockup at the top of the home page. It settles in once when the page appears, before
/// the cards fade in under it, so the page opens on the brand rather than on a flash of controls.
struct HomeHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        NativeLockup(size: HomeLayout.heroSize, layout: .stacked)
            .foregroundStyle(.dsTextPrimary)
            .opacity(isShown ? 1 : 0)
            .scaleEffect(isShown ? 1 : HomeLayout.heroEntranceScale)
            .offset(y: isShown ? 0 : HomeLayout.heroEntranceOffset)
            .accessibilityAddTraits(.isHeader)
            .onAppear {
                withAnimation(reduceMotion ? nil : HomeLayout.heroEntrance) {
                    isShown = true
                }
            }
    }
}

#Preview("Hero - Light") {
    HomeHero()
        .padding(DS.Space.xxxl)
        .background(.dsBackground)
        .preferredColorScheme(.light)
}

#Preview("Hero - Dark") {
    HomeHero()
        .padding(DS.Space.xxxl)
        .background(.dsBackground)
        .preferredColorScheme(.dark)
}
