import CodeThemes
import SwiftUI

/// One theme in Try On's list: its chip and name. The highlighted row shows Return, which keeps it;
/// the theme the user has says "In use".
struct ThemeTryOnRow: View {
    let theme: CodeTheme
    let appearance: CodeAppearance
    let isHighlighted: Bool
    let isInUse: Bool
    let highlight: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: highlight) {
            HStack(spacing: DS.TryOn.rowGap) {
                CodeThemeChip(theme: theme, appearance: appearance)
                Text(theme.name)
                    .font(isHighlighted ? .dsCalloutMedium : .dsCallout)
                    .foregroundStyle(isHighlighted ? Color.dsTextPrimary : .dsTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Both on the theme in use while it's highlighted, so what you have stays marked.
                if isInUse {
                    Text("In use")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
                if isHighlighted {
                    Image(systemName: "return")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .frame(maxWidth: .infinity, minHeight: max(DS.TryOn.rowHeight, DS.Size.minimumHitTarget))
            .background(
                isHighlighted ? Color.dsSelected : isHovered ? .dsHover : .clear,
                in: .rect(cornerRadius: DS.Radius.row, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .padding(.horizontal, DS.Space.md)
        .accessibilityLabel(theme.name)
        .accessibilityValue(isInUse ? "In use" : "")
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Try On - Rows") {
    DSPreviewPair {
        VStack(spacing: 0) {
            ThemeTryOnRow(theme: .native, appearance: .dark, isHighlighted: false, isInUse: true) {}
            ThemeTryOnRow(theme: .tokyoNight, appearance: .dark, isHighlighted: true, isInUse: false) {}
            ThemeTryOnRow(theme: .nord, appearance: .dark, isHighlighted: false, isInUse: false) {}
        }
        .frame(width: DS.Size.sidebarWidth)
    }
}
#endif
