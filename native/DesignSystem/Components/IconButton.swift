import SwiftUI

/// A square icon-only button: secondary glyph that turns primary on a hover wash (Factory
/// `IconButton` text variant, Conductor's `iconXs` ghost button). The label is its tooltip and
/// accessibility label.
public struct IconButton: View {
    public enum Size: Sendable {
        /// 24pt, 12pt glyph.
        case small
        /// 28pt, 13pt glyph.
        case medium
        /// 32pt, 14pt glyph.
        case large

        var side: CGFloat {
            switch self {
            case .small: DS.Size.controlXS
            case .medium: DS.Size.controlSM
            case .large: DS.Size.controlMD
            }
        }

        var glyph: CGFloat {
            switch self {
            case .small: 12
            case .medium: 13
            case .large: 14
            }
        }
    }

    let label: String
    let systemImage: String
    let size: Size
    let isActive: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    /// - Parameter isActive: Keeps the hover fill, for a toggle that is on.
    public init(
        _ label: String,
        systemImage: String,
        size: Size = .small,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.size = size
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size.glyph, weight: .regular))
                .frame(width: size.side, height: size.side)
                .contentShape(.rect)
                .dsHitTarget(size.side)
        }
        .buttonStyle(IconButtonStyle(isHovered: isHovered && isEnabled, isActive: isActive))
        .opacity(isEnabled ? 1 : 0.5)
        .help(label)
        .accessibilityLabel(label)
        .trackHover($isHovered)
    }
}

private struct IconButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        let isHighlighted = isHovered || isActive || configuration.isPressed
        configuration.label
            .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
            .background(
                configuration.isPressed ? .dsPressed : isActive ? .dsSelected : isHovered ? .dsHover : .clear, in: shape
            )
            .dsFocusShape(shape)
    }
}

#Preview("Icon buttons") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            IconButton("Settings", systemImage: "gearshape") {}
            IconButton("Filter", systemImage: "line.3.horizontal.decrease", size: .medium) {}
            IconButton("Add", systemImage: "plus", size: .large, isActive: true) {}
            IconButton("Disabled", systemImage: "trash") {}.disabled(true)
        }
    }
}
