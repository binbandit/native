import SwiftUI

/// The outlined 28pt chip every composer control uses (Factory `OptionsPrimary`): 1pt outline,
/// 4pt radius, 12pt text; hover fills it and darkens the outline. `isOn` inverts it, the way
/// Factory marks a non-default mode. `isSquare` makes an icon button ("+", "?", the mic).
/// `isOpen` dashes the outline in the primary color while the pill's popover or menu is showing
/// (Factory's model selector, `border-style: dashed`).
///
///     Button("Plan", action: toggle).buttonStyle(.pill(isOn: isPlanning))
///     Button("Model") { isPickerOpen = true }.buttonStyle(.pill(isOpen: isPickerOpen))
public struct PillButtonStyle: ButtonStyle {
    let isOn: Bool
    let isSquare: Bool
    let isOpen: Bool

    public init(isOn: Bool = false, isSquare: Bool = false, isOpen: Bool = false) {
        self.isOn = isOn
        self.isSquare = isSquare
        self.isOpen = isOpen
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pillChrome(isOn: isOn, isSquare: isSquare, isOpen: isOpen, isPressed: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    /// The composer's outlined chip.
    public static var pill: PillButtonStyle { PillButtonStyle() }

    public static func pill(isOn: Bool = false, isSquare: Bool = false, isOpen: Bool = false) -> PillButtonStyle {
        PillButtonStyle(isOn: isOn, isSquare: isSquare, isOpen: isOpen)
    }
}

extension View {
    /// Draws the composer chip around a label; for `Menu` labels, which ignore custom button styles.
    public func pillChrome(
        isOn: Bool = false,
        isSquare: Bool = false,
        isOpen: Bool = false,
        isPressed: Bool = false
    ) -> some View {
        modifier(PillChrome(isOn: isOn, isSquare: isSquare, isOpen: isOpen, isPressed: isPressed))
    }
}

private struct PillChrome: ViewModifier {
    let isOn: Bool
    let isSquare: Bool
    let isOpen: Bool
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        let isHighlighted = isHovered && isEnabled
        content
            .font(.dsBody)
            .tracking(DS.Tracking.tight)
            .lineLimit(1)
            .labelStyle(PillLabelStyle(isIconOnly: isSquare))
            .foregroundStyle(isOn ? .dsTextInverse : .dsTextPrimary)
            .padding(.horizontal, isSquare ? 0 : DS.Composer.pillPadding)
            .frame(minWidth: DS.Size.composerPill, minHeight: DS.Size.composerPill)
            .frame(width: isSquare ? DS.Size.composerPill : nil)
            .background(fill(isHighlighted: isHighlighted), in: shape)
            .overlay {
                // Chromium draws a 1px dashed border as 3px dashes.
                shape.strokeBorder(
                    stroke(isHighlighted: isHighlighted),
                    style: StrokeStyle(lineWidth: 1, dash: isOpen && !isOn ? [3, 3] : [])
                )
            }
            .contentShape(shape)
            .dsHitTarget(DS.Size.composerPill)
            .dsFocusShape(shape)
            .opacity(isEnabled ? 1 : 0.5)
            .trackHover($isHovered)
    }

    private func fill(isHighlighted: Bool) -> Color {
        if isOn {
            isPressed || isHighlighted ? .dsTextSecondary : .dsTextPrimary
        } else if isPressed {
            .dsPressed
        } else if isHighlighted {
            .dsSelected
        } else {
            .clear
        }
    }

    private func stroke(isHighlighted: Bool) -> Color {
        if isOn {
            .clear
        } else if isOpen {
            .dsTextPrimary
        } else if isHighlighted || isPressed {
            .dsBorderHover
        } else {
            .dsBorder
        }
    }
}

/// Icon then title, 6pt apart, the icon at 11pt; square pills show the icon alone, through the
/// system's icon-only style so the title stays the accessibility label.
private struct PillLabelStyle: LabelStyle {
    let isIconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isIconOnly {
            Label {
                configuration.title
            } icon: {
                configuration.icon
                    .font(.system(size: 11, weight: .regular))
            }
            .labelStyle(.iconOnly)
        } else {
            HStack(spacing: DS.Space.sm) {
                configuration.icon
                    .font(.system(size: 11, weight: .regular))
                configuration.title
            }
        }
    }
}

#Preview("Pills") {
    DSPreviewPair {
        HStack(spacing: DS.Composer.controlSpacing) {
            Button("Attach", systemImage: "plus") {}.buttonStyle(.pill(isSquare: true))
            Button("Normal Mode") {}.buttonStyle(.pill)
            Button("Plan Mode") {}.buttonStyle(.pill(isOn: true))
            Button("Auto Model") {}.buttonStyle(.pill(isOpen: true))
            Button("Skills") {}.buttonStyle(.pill).disabled(true)
        }
    }
}
