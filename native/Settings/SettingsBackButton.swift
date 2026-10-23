import SwiftUI

/// Leaves Settings: a muted arrow and "Back" that brighten on hover, Escape as the shortcut.
struct SettingsBackButton: View {
    let action: () -> Void
    @Environment(\.settingsPlainly) private var plainly

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if plainly {
                label
                    .padding(.horizontal, DS.Space.md)
                    .frame(height: DS.Size.controlSM)
                    .dsGlassEffect(in: .capsule)
            } else {
                label
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.Size.controlSM)
        .trackHover($isHovered)
        .help("Back (Esc)")
    }

    private var label: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: plainly ? "chevron.left" : "arrow.left")
                .font(.system(size: SettingsMetrics.navGlyph, weight: .thin))
            Text("Back")
                .settingsText(plainly ? .bodyMedium : .body)
        }
        .foregroundStyle(plainly || isHovered ? Color.dsTextPrimary : Color.dsTextSecondary)
    }
}

#if DEBUG
#Preview("Back button") {
    DSPreviewPair {
        SettingsBackButton {}
    }
}

#Preview("Plainly - Back button") {
    DSPreviewPair { SettingsBackButton {} }
        .environment(\.settingsPlainly, true)
}
#endif
