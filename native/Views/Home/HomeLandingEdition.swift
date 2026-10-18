import SwiftUI

/// How the home page's lockup looks for one build and season, resolved in one place so every
/// combination is deliberate: each release channel matches its app icon, and Halloween dresses
/// whichever channel is running.
///
/// | Channel | Everyday | Halloween |
/// | --- | --- | --- |
/// | Stable | the plain mark | Regular ghosts |
/// | Beta | amber and cream mark, Beta badge | Beta ghosts, Beta badge |
/// | Nightly | night sky, Nightly badge | Nightly ghosts under the orange moon and bats, Nightly badge |
/// | Dev | the plain mark, Dev badge | Regular ghosts (until a dev edition exists), Dev badge |
struct HomeLandingEdition: Equatable {
    /// A channel's tell under the lockup.
    struct ChannelBadge: Equatable {
        let title: String
        let tone: Badge.Tone
    }

    let markStyle: NativeMarkStyle
    let showsNightSky: Bool
    let badge: ChannelBadge?
    /// The lockup's accessibility label, the channel's own name: "Native Beta".
    let name: String
    let isHalloween: Bool

    init(channel: ReleaseChannel, isHalloween: Bool) {
        self.isHalloween = isHalloween
        name = channel.displayName
        showsNightSky = channel == .nightly
        switch channel {
        case .stable:
            markStyle = isHalloween ? .halloween(.regular) : .standard
            badge = nil
        case .beta:
            markStyle = isHalloween ? .halloween(.beta) : .beta
            // Amber, like the Beta icon.
            badge = ChannelBadge(title: "Beta", tone: .warning)
        case .nightly:
            markStyle = isHalloween ? .halloween(.nightly) : .standard
            badge = ChannelBadge(title: "Nightly", tone: .neutral)
        case .dev:
            markStyle = isHalloween ? .halloween(.regular) : .standard
            // Blue, a color no shipping build uses, so a build from source is never taken for an
            // installed one.
            badge = ChannelBadge(title: "Dev", tone: .info)
        }
    }
}
