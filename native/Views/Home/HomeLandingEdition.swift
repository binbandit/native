import AppAppearance
import SwiftUI

/// How the home page's lockup looks for one build and occasion, resolved in one place so every
/// combination is deliberate: each release channel matches its app icon, and a celebration (or a
/// plugin icon set's palette) dresses whichever channel is running.
///
/// | Channel | Everyday | Halloween | Día de Muertos |
/// | --- | --- | --- | --- |
/// | Stable | the plain mark | Regular ghosts | Regular marigold and rosa |
/// | Beta | amber and cream mark, Beta badge | Beta ghosts | Beta marigold and cream |
/// | Nightly | night sky, Nightly badge | Nightly ghosts, orange moon and bats | Nightly marigold and lavender, night sky |
/// | Dev | the plain mark, Dev badge | Regular ghosts, Dev badge | Regular, Dev badge |
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
    /// What it's dressed for, for accessibility: "Halloween".
    let occasion: String?

    var isHalloween: Bool {
        if case .halloween = markStyle { return true }
        return false
    }

    /// The Home marks this build draws, for validating contributions that name one.
    static let drawableMarks: Set<String> = [
        FirstPartyCelebrations.HomeMark.halloween, FirstPartyCelebrations.HomeMark.diaDeMuertos,
    ]

    init(channel: ReleaseChannel, look: HomeLook? = nil, occasion: String? = nil) {
        name = channel.displayName
        self.occasion = look == nil ? nil : occasion
        showsNightSky = channel == .nightly
        badge =
            switch channel {
            case .stable: nil
            // Amber, like the Beta icon.
            case .beta: ChannelBadge(title: "Beta", tone: .warning)
            case .nightly: ChannelBadge(title: "Nightly", tone: .neutral)
            // Blue, a color no shipping build uses, so a build from source is never taken for an
            // installed one.
            case .dev: ChannelBadge(title: "Dev", tone: .info)
            }
        markStyle = Self.style(for: look, channel: channel)
    }

    private static func style(for look: HomeLook?, channel: ReleaseChannel) -> NativeMarkStyle {
        switch look {
        case .mark(FirstPartyCelebrations.HomeMark.halloween):
            switch channel {
            case .beta: .halloween(.beta)
            case .nightly: .halloween(.nightly)
            case .stable, .dev: .halloween(.regular)
            }
        case .mark(FirstPartyCelebrations.HomeMark.diaDeMuertos):
            switch channel {
            case .beta: .diaDeMuertos(.beta)
            case .nightly: .diaDeMuertos(.nightly)
            case .stable, .dev: .diaDeMuertos(.regular)
            }
        case .artwork(let icons):
            icons[variant(channel)].map { pair in
                .artwork(
                    NativeEditionArtwork(
                        id: "\(pair)", light: PlatformAppIcon.preview(pair.light),
                        dark: PlatformAppIcon.preview(pair.dark)))
            } ?? (channel == .beta ? .beta : .standard)
        case .palette(let palette):
            twoTone(palette).map(NativeMarkStyle.twoTone) ?? (channel == .beta ? .beta : .standard)
        case .mark, nil:
            channel == .beta ? .beta : .standard
        }
    }

    /// The icon family each channel wears, as its app icon does.
    private static func variant(_ channel: ReleaseChannel) -> AppIconVariant {
        switch channel {
        case .stable: .stable
        case .beta: .beta
        case .nightly: .nightly
        case .dev: .development
        }
    }

    private static func twoTone(_ palette: IconSetPalette) -> NativeTwoTonePalette? {
        guard let lightLeft = palette.light.first, let lightRight = palette.light.dropFirst().first,
            let darkLeft = palette.dark.first, let darkRight = palette.dark.dropFirst().first
        else { return nil }
        return NativeTwoTonePalette(
            light: (color(lightLeft), color(lightRight)), dark: (color(darkLeft), color(darkRight)))
    }

    private static func color(_ hex: HexColor) -> Color {
        Color(.sRGB, red: hex.red, green: hex.green, blue: hex.blue)
    }
}
