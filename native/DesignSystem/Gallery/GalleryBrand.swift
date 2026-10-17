import SwiftUI

// Gallery sections for the brand and the accent palettes.

struct GalleryBrand: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            HStack(alignment: .center, spacing: DS.Space.xxl) {
                NativeMark()
                    .frame(width: 96, height: 62)
                NativeLockup(size: 13)
                NativeLockup(size: 22)
            }
            HStack(alignment: .center, spacing: DS.Space.xxxl) {
                NativeLockup(size: 24, layout: .stacked)
                    .nightSky(isEnabled: true)
                    .frame(width: 200, height: 220)
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    HStack(spacing: DS.Space.sm) {
                        NativeLockup(size: 13)
                        NightlyMark()
                            .foregroundStyle(.dsTextTertiary)
                    }
                    Text("Nightly: the sky around the landing logo, the moon beside the sidebar title.")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: 220, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.dsTextPrimary)
    }
}

/// Each icon theme's accent on the controls that use it.
struct GalleryAccentPalettes: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(DSAccentPalette.all) { palette in
                HStack(spacing: DS.Space.md) {
                    Text(palette.name)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                        .frame(width: 60, alignment: .leading)
                    Button("Primary") {}.buttonStyle(.ds(.primary))
                    UpdateButton(version: "1.4.0") {}
                    ComposerSendButton {}
                    EffortBars(level: 2)
                    StatusDot()
                    Text("Accent text")
                        .font(.dsBody)
                        .foregroundStyle(.dsAccentText)
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .fill(.dsAccentSubtle)
                        .frame(width: 28, height: 20)
                }
                .dsAccentPalette(palette)
            }
        }
    }
}
