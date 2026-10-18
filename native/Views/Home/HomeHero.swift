import SwiftUI

/// Native's lockup at the top of the home page. It settles in once when the page appears, before
/// the cards fade in under it, so the page opens on the brand rather than on a flash of controls.
/// Nightly builds set it in the Nightly icon's sky and say so under the name, so it's always clear
/// which build is running. While the user has the Halloween app icon, the emblem turns to that
/// icon's ghosts for this channel (and the Nightly sky gets its orange moon and bats), so the page
/// always matches the Dock.
struct HomeHero: View {
    @Environment(\.releaseChannel) private var releaseChannel
    /// Optional, so previews and other hosts without icon preferences get the everyday mark.
    @Environment(AppIconPreferences.self) private var iconPreferences: AppIconPreferences?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false

    var body: some View {
        VStack(spacing: DS.Space.md) {
            NativeLockup(size: HomeLayout.heroSize, layout: .stacked, halloween: halloween)
                .nightSky(isEnabled: releaseChannel.isNightly, isHalloween: halloween != nil)
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

    /// The Halloween edition matching the app icon, while the user has it.
    private var halloween: NativeHalloweenEdition? {
        guard iconPreferences?.isHalloweenActive == true else { return nil }
        return switch releaseChannel {
        case .stable, .dev: .regular
        case .beta: .beta
        case .nightly: .nightly
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
