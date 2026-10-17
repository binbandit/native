import SwiftUI

/// Leaves Settings (Conductor: a muted arrow and "Back" that brighten on hover, Escape as the
/// shortcut).
struct SettingsBackButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "arrow.left")
                    .font(.system(size: SettingsMetrics.navGlyph, weight: .thin))
                Text("Back")
                    .settingsText(.body)
            }
            .foregroundStyle(isHovered ? Color.dsTextPrimary : Color.dsTextSecondary)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help("Back (Esc)")
    }
}
