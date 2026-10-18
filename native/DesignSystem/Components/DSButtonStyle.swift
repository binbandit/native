import SwiftUI

/// Factory's buttons (core-ui v2 `Button`): 12pt text, 12pt horizontal padding, 1pt border, 4pt
/// radius; colors change on hover and press with no motion in and a 100ms fade out.
///
///     Button("Create") { … }.buttonStyle(.ds(.primary))
///     Button("More", systemImage: "ellipsis") { … }.buttonStyle(.ds(.ghost, iconOnly: true))
///
/// An icon-only button still takes a title: it's what VoiceOver says and what the tooltip should
/// repeat. Never give a DS button a bare `Image` label.
public struct DSButtonStyle: ButtonStyle {
    public enum Variant: Sendable {
        /// Accent fill, black text (Factory `Primary`).
        case primary
        /// Outlined (Factory `Secondary`).
        case secondary
        /// Text only, filling on hover (Factory `Text`, with Conductor's ghost hover wash).
        case ghost
        /// Solid red (Factory `Destructive`).
        case destructive
        /// The foreground color as the fill (Factory `NeutralPrimary`).
        case neutral
    }

    public enum Size: Sendable {
        /// 24pt, Factory's default.
        case small
        /// 28pt.
        case medium
        /// 32pt.
        case large

        var height: CGFloat {
            switch self {
            case .small: DS.Size.controlXS
            case .medium: DS.Size.controlSM
            case .large: DS.Size.controlMD
            }
        }
    }

    let variant: Variant
    let size: Size
    let isIconOnly: Bool

    /// - Parameter isIconOnly: Shows a `Label`'s icon alone in a square button, keeping its title
    ///   as the accessibility label.
    public init(variant: Variant = .secondary, size: Size = .small, isIconOnly: Bool = false) {
        self.variant = variant
        self.size = size
        self.isIconOnly = isIconOnly
    }

    public func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(configuration: configuration, variant: variant, size: size, isIconOnly: isIconOnly)
    }
}

extension ButtonStyle where Self == DSButtonStyle {
    public static func ds(
        _ variant: DSButtonStyle.Variant,
        size: DSButtonStyle.Size = .small,
        iconOnly: Bool = false
    ) -> DSButtonStyle {
        DSButtonStyle(variant: variant, size: size, isIconOnly: iconOnly)
    }
}

private struct DSButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: DSButtonStyle.Variant
    let size: DSButtonStyle.Size
    let isIconOnly: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        configuration.label
            .labelStyle(DSButtonLabelStyle(isIconOnly: isIconOnly))
            .font(.dsBody)
            .tracking(DS.Tracking.tight)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, isIconOnly ? 0 : DS.Space.lg)
            .frame(minWidth: isIconOnly ? size.height : nil, minHeight: size.height)
            .background(fill, in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: 1) }
            .contentShape(shape)
            .dsHitTarget(size.height)
            .dsFocusShape(shape)
            .trackHover($isHovered)
    }

    private var isHighlighted: Bool { isEnabled && (isHovered || configuration.isPressed) }
    private var isPressed: Bool { isEnabled && configuration.isPressed }

    private var foreground: Color {
        guard isEnabled else { return .dsTextTertiary }
        return switch variant {
        case .primary: .dsTextOnAccent
        case .secondary: .dsTextPrimary
        case .ghost: isHighlighted ? .dsTextPrimary : .dsTextSecondary
        case .destructive: .white
        case .neutral: .dsTextInverse
        }
    }

    private var fill: Color {
        guard isEnabled else { return variant == .ghost ? .clear : .dsSelected }
        return switch variant {
        case .primary: isPressed ? .dsAccentPressed : isHighlighted ? .dsAccentHover : .dsAccent
        case .secondary: isPressed ? .dsPressed : isHighlighted ? .dsHover : .dsSurface
        case .ghost: isPressed ? .dsPressed : isHighlighted ? .dsHover : .clear
        case .destructive: isPressed ? .dsDangerFillPressed : isHighlighted ? .dsDangerFillHover : .dsDangerFill
        case .neutral: isHighlighted ? .dsTextSecondary : .dsTextPrimary
        }
    }

    private var border: Color {
        guard isEnabled, variant == .secondary else { return .clear }
        return isHighlighted ? .dsBorderHover : .dsBorder
    }
}

/// Icon and title 6pt apart, the icon a size below the text; or the icon alone, through the
/// system's icon-only style so the title stays the accessibility label.
private struct DSButtonLabelStyle: LabelStyle {
    let isIconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isIconOnly {
            Label {
                configuration.title
            } icon: {
                configuration.icon
                    .font(.system(size: 12, weight: .regular))
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

#Preview("Buttons") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Button("Primary") {}.buttonStyle(.ds(.primary))
                Button("Secondary") {}.buttonStyle(.ds(.secondary))
                Button("Ghost", systemImage: "arrow.clockwise") {}.buttonStyle(.ds(.ghost))
                Button("More", systemImage: "ellipsis") {}.buttonStyle(.ds(.ghost, iconOnly: true))
            }
            HStack(spacing: DS.Space.md) {
                Button("Delete") {}.buttonStyle(.ds(.destructive, size: .medium))
                Button("Neutral") {}.buttonStyle(.ds(.neutral, size: .medium))
                Button("Disabled") {}.buttonStyle(.ds(.secondary, size: .large)).disabled(true)
            }
        }
    }
}
