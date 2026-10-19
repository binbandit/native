import SwiftUI

/// One line of a composer pill's popover (autonomy levels, modes): an optional symbol, a name over
/// a plain description, an optional note on what it can't do here, and a check or a lock.
struct ComposerPickerRow: View {
    enum Trailing: Equatable {
        case none
        case checked(dimmed: Bool)
        case locked
    }

    var symbol: String?
    let title: String
    let detail: String?
    /// What the choice can't do as asked here, said plainly under the description.
    var note: String?
    let trailing: Trailing
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.dsBody)
                        .foregroundStyle(isEnabled ? .dsTextSecondary : .dsTextTertiary)
                        .frame(width: DS.Size.statusGlyph)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                        .font(.dsCallout)
                        .foregroundStyle(isEnabled ? .dsTextPrimary : .dsTextTertiary)
                    if let detail {
                        Text(detail)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note {
                        Label(note, systemImage: "info.circle")
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DS.Space.xxs)
                    }
                }
                Spacer(minLength: 0)
                trailingMark
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(
                isHovered && isEnabled ? Color.dsSelected : .clear,
                in: .rect(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .trackHover($isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(trailing == .checked(dimmed: false) ? .isSelected : [])
    }

    @ViewBuilder
    private var trailingMark: some View {
        switch trailing {
        case .none:
            EmptyView()
        case .checked(let dimmed):
            // The accent can be monochrome, so the current choice gets a check, not only a color.
            Image(systemName: "checkmark")
                .font(.dsCaption)
                .foregroundStyle(dimmed ? .dsTextTertiary : .dsAccentText)
                .accessibilityLabel("Current")
        case .locked:
            Image(systemName: "lock.fill")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityLabel("Locked")
        }
    }
}
