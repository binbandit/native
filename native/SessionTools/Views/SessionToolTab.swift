import SwiftUI

/// A tab in a place's strip: the tool's glyph, its name and what it says, selected while its pane
/// shows.
struct SessionToolTab: View {
    let title: String
    let systemImage: String
    var accessory: SessionToolFact.Accessory?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: systemImage)
                    .font(.dsCaption)
                    .fixedSize()
                    .foregroundStyle(isSelected ? .dsTextPrimary : .dsTextTertiary)
                Text(title)
                    .lineLimit(1)
                SessionToolFactAccessory(accessory: accessory)
                    .fixedSize()
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
        .fixedSize(horizontal: false, vertical: true)
        .help(title)
        .trackHover($isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Changes tab - Selected and unselected") {
    DSPreviewPair {
        ForEach([false, true], id: \.self) { selected in
            SessionToolTab(
                title: "Changes", systemImage: "plus.forwardslash.minus",
                accessory: .diff(added: 12, removed: 3), isSelected: selected, action: {})
        }
    }
}
#Preview("Tool tab - Long name beside Close") {
    DSPreviewPair {
        HStack {
            SessionToolTab(
                title: "Release verification and acceptance checks", systemImage: "checklist",
                accessory: .working, isSelected: true, action: {})
            Spacer(minLength: DS.Space.sm)
            IconButton("Close Side Panel", systemImage: "xmark", action: {})
        }
        .frame(width: DS.SessionTools.sidePanelIdealWidth)
        .padding(DS.Space.md)
    }
}
#endif
