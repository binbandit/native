import AppAppearance
import SwiftUI

/// A celebration's edition for this build: its app icon when it's here, otherwise its bundled
/// thumbnail, otherwise its Home mark on a tile. Previews follow the running channel, so a Nightly
/// build previews the Nightly edition.
struct CelebrationPreview: View {
    let event: CelebrationEvent
    var size: CGFloat = CelebrationMetrics.previewTile

    @Environment(\.releaseChannel) private var channel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CelebrationCenter.self) private var center

    var body: some View {
        Group {
            if let icon = event.icon(for: center.variant, isDark: colorScheme == .dark)
                ?? event.iconSet?.thumbnail?.image(isDark: colorScheme == .dark)
            {
                PlatformAppIcon.preview(icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                CelebrationHomePreview(look: event.homeLook ?? event.iconSet?.home, channel: channel)
                    .padding(size * 0.2)
                    .frame(width: size, height: size)
                    .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.panel, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                            .strokeBorder(.dsSeparator, lineWidth: 1)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The Home emblem as a celebration would dress it, or the plain emblem in a muted color when it has
/// no Home edition yet.
struct CelebrationHomePreview: View {
    let look: HomeLook?
    let channel: ReleaseChannel

    var body: some View {
        if let look {
            NativeEditionMark(style: HomeLandingEdition(channel: channel, look: look).markStyle)
                .foregroundStyle(.dsTextPrimary)
                // The decorations reach past the emblem; keep them inside the tile.
                .scaleEffect(CelebrationMetrics.decoratedMarkScale)
        } else {
            NativeMark()
                .fill(.dsTextQuaternary)
                .aspectRatio(NativeMark.aspectRatio, contentMode: .fit)
        }
    }
}
