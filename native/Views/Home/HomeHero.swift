import SwiftUI

/// Native's lockup at the top of the home page, in the edition that matches the app icon in the
/// Dock (`HomeLandingEdition`): a channel badge on Beta, Nightly and Dev builds, the night sky on
/// Nightly, and the edition of whichever celebration is showing. It settles in once when
/// the page appears, before the cards fade in under it, so the page opens on the brand rather than
/// on a flash of controls.
struct HomeHero: View {
    @Environment(\.releaseChannel) private var releaseChannel
    /// Optional, so previews and other hosts without them get the everyday mark.
    @Environment(AppIconPreferences.self) private var iconPreferences: AppIconPreferences?
    @Environment(CelebrationCenter.self) private var celebrations: CelebrationCenter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    private var edition: HomeLandingEdition {
        if let look = celebrations?.homeLook {
            return HomeLandingEdition(channel: releaseChannel, look: look, occasion: celebrations?.homeTitle)
        }
        return HomeLandingEdition(
            channel: releaseChannel, look: iconPreferences?.baseHomeLook,
            occasion: iconPreferences?.baseIconSet?.name.resolved())
    }

    var body: some View {
        let edition = edition
        VStack(spacing: DS.Space.md) {
            NativeLockup(size: HomeLayout.heroSize, layout: .stacked, style: edition.markStyle)
                .nightSky(isEnabled: edition.showsNightSky, isHalloween: edition.isHalloween)
            if let badge = edition.badge {
                Badge(badge.title, tone: badge.tone, style: .mono)
                    // Keeps the sky's stars from showing through the letters.
                    .background(.dsBackground, in: .rect(cornerRadius: DS.Radius.small))
            }
        }
        .foregroundStyle(.dsTextPrimary)
        .opacity(isShown ? 1 : 0)
        .scaleEffect(isShown ? 1 : HomeLayout.heroEntranceScale)
        .offset(y: isShown ? 0 : HomeLayout.heroEntranceOffset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(edition.name)
        .accessibilityValue(edition.occasion ?? "")
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

#Preview("Hero - Beta") {
    HomeHero()
        .padding(DS.Space.xxxl)
        .background(.dsBackground)
        .environment(\.releaseChannel, .beta)
}

#Preview("Hero - Nightly") {
    HomeHero()
        .padding(DS.Space.xxxl * 3)
        .background(.dsBackground)
        .environment(\.releaseChannel, .nightly)
        .preferredColorScheme(.dark)
}
