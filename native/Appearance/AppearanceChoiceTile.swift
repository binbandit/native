import OSLog  // DEBUG-PROBE
import SwiftUI

/// One choice among Settings ▸ Appearance's looks (light or dark, Paper or Wool): a preview of the
/// app in that look and its name, ringed in the accent and checked while it's the current one.
struct AppearanceChoiceTile<Preview: View>: View {
    let title: String
    let isSelected: Bool
    /// What VoiceOver calls it, since the preview says nothing: "Wool light mode".
    let accessibilityLabel: String
    let select: () -> Void
    @ViewBuilder var preview: Preview

    @State private var isHovered = false

    var body: some View {
        let _ = DebugProbe.log.notice("tile \(title, privacy: .public) selected=\(isSelected)")  // DEBUG-PROBE
        Button(action: select) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                preview
                    .frame(height: TileMetrics.height)
                    .padding(TileMetrics.ring)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.panel + TileMetrics.ring, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.dsAccent : isHovered ? .dsBorderHover : .clear,
                                lineWidth: TileMetrics.ringWidth)
                    }
                HStack(spacing: DS.Space.xs) {
                    Text(title)
                        .settingsText(.bodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.dsAccent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, TileMetrics.ring)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private enum TileMetrics {
    static let height: CGFloat = 132
    /// The selection ring sits this far outside the preview, clear of its edge.
    static let ring: CGFloat = 3
    static let ringWidth: CGFloat = 2
}
