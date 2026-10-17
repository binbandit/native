import SwiftUI

/// A volume slider between quiet and loud speaker glyphs that plays the sound when the user lets go,
/// so they hear the level they picked.
struct VolumeSlider: View {
    @Binding var volume: Double
    let onRelease: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            Slider(value: $volume, in: 0...1) { isEditing in
                if !isEditing {
                    onRelease()
                }
            }
            .controlSize(.small)
            .tint(.dsTextPrimary)
            .accessibilityLabel("Volume")
            .accessibilityValue(volume.formatted(.percent.precision(.fractionLength(0))))
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        }
        .font(.system(size: SettingsMetrics.chevronGlyph))
        .foregroundStyle(.dsTextTertiary)
    }
}
