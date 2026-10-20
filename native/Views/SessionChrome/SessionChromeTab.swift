#if DEBUG && NATIVE_SESSION_CHROME_WIP
import SwiftUI

/// A tab in a chrome place's strip: a glyph, a name and its live fact, selected while its pane
/// shows. The same in the side panel and the workbench.
struct SessionChromeTab: View {
    let title: String
    let systemImage: String
    var fact: SessionChromeFact?
    let isSelected: Bool
    var help: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: systemImage)
                    .font(.dsCaption)
                    .foregroundStyle(isSelected ? .dsTextPrimary : .dsTextTertiary)
                Text(title)
                    .lineLimit(1)
                if let fact {
                    SessionChromeFactBadge(fact: fact)
                }
            }
            .font(.dsBodyMedium)
            .foregroundStyle(isSelected || isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.md)
            .frame(height: DS.Size.controlXS)
            .background(
                isSelected ? Color.dsSelected : isHovered ? Color.dsHover : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .trackHover($isHovered)
        .help(help ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
