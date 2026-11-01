import SwiftUI

struct ComposerRowMenuOption: View {
    let choice: ComposerRowState.Choice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: choice.unavailable == nil ? "checkmark" : "lock")
                    .font(.dsCaption)
                    .opacity(choice.isSelected || choice.unavailable != nil ? 1 : 0)
                    .frame(width: DS.ComposerRow.checkWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(choice.title).font(.dsBody).foregroundStyle(.dsTextPrimary)
                    if !choice.detail.isEmpty || choice.unavailable != nil {
                        Text(choice.unavailable ?? choice.detail)
                            .font(.dsCaption).foregroundStyle(.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(minHeight: DS.ComposerRow.menuRowHeight, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(ComposerRowControlStyle(selected: choice.isSelected))
        .disabled(choice.unavailable != nil)
        .accessibilityLabel(choice.title)
        .accessibilityValue(choice.isSelected ? "Selected" : "")
        .accessibilityHint(choice.unavailable ?? choice.detail)
    }
}

struct ComposerRowControlStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.dsTextSecondary)
            .background(
                configuration.isPressed ? Color.dsPressed : selected ? .dsSelected : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.row)
            )
            .dsFocusShape(RoundedRectangle(cornerRadius: DS.Radius.row))
    }
}

#if DEBUG
#Preview("Composer menu option - Selected and unavailable") {
    DSPreviewPair {
        VStack {
            ComposerRowMenuOption(choice: .init(id: "selected", title: "Sonnet", isSelected: true)) {}
            ComposerRowMenuOption(
                choice: .init(id: "locked", title: "Full access", unavailable: "Managed by your organization")
            ) {}
        }.frame(width: DS.ComposerRow.menuWidth)
    }
}
#endif
