import SwiftUI

/// Native's lockup at the top of the home page. It settles in once when the page appears, before
/// the cards fade in under it, so the page opens on the brand rather than on a flash of controls.
/// Nightly builds set it in the Nightly icon's sky and say so under the name, so it's always clear
/// which build is running.
struct HomeHero: View {
    @Environment(\.releaseChannel) private var releaseChannel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        VStack(spacing: DS.Space.md) {
            NativeLockup(size: HomeLayout.heroSize, layout: .stacked)
                .nightSky(isEnabled: releaseChannel.isNightly)
            if releaseChannel.isNightly {
                Badge("Nightly", style: .mono)
                    // Keeps the sky's stars from showing through the letters.
                    .background(.dsBackground, in: .rect(cornerRadius: DS.Radius.small))
            }
        }
        .foregroundStyle(.dsTextPrimary)
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown ? 1 : HomeLayout.heroEntranceScale)
        .offset(y: isShown ? 0 : HomeLayout.heroEntranceOffset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(releaseChannel.displayName)
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

#Preview("Hero - Nightly") {
    HomeHero()
        .padding(DS.Space.xxxl * 3)
        .background(.dsBackground)
        .environment(\.releaseChannel, .nightly)
        .preferredColorScheme(.dark)
}
