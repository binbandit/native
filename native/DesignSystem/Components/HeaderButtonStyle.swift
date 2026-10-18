import SwiftUI

/// The window header's outlined control, the same chrome as the Open In split button: 24pt tall,
/// the surface fill, a 1pt border and a 4pt radius, a hover wash and a pressed fill. `isOn` keeps it
/// selected and bright while the panel it toggles is open; `isIconOnly` makes it 28pt square-ish, as
/// wide as Open In's halves. It draws its own outline, so its `ToolbarItem` hides the shared glass:
///
///     ToolbarItem {
///         Button("Show Terminal", systemImage: "apple.terminal", action: toggle)
///             .buttonStyle(.header(isOn: isShowing, iconOnly: true))
///     }
///     .sharedBackgroundVisibility(.hidden)
public struct HeaderButtonStyle: ButtonStyle {
    let isOn: Bool
    let isIconOnly: Bool

    public init(isOn: Bool = false, isIconOnly: Bool = false) {
        self.isOn = isOn
        self.isIconOnly = isIconOnly
    }

    public func makeBody(configuration: Configuration) -> some View {
        HeaderButtonBody(configuration: configuration, isOn: isOn, isIconOnly: isIconOnly)
    }
}

extension ButtonStyle where Self == HeaderButtonStyle {
    /// The window header's outlined control.
    public static func header(isOn: Bool = false, iconOnly: Bool = false) -> HeaderButtonStyle {
        HeaderButtonStyle(isOn: isOn, isIconOnly: iconOnly)
    }
}

private struct HeaderButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool
    let isIconOnly: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        let isHighlighted = isEnabled && (isHovered || configuration.isPressed || isOn)
        configuration.label
            .labelStyle(HeaderLabelStyle(isIconOnly: isIconOnly))
            .font(.dsBody)
            .tracking(DS.Tracking.tight)
            .lineLimit(1)
            .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, isIconOnly ? 0 : DS.Space.sm)
            .frame(minWidth: isIconOnly ? HeaderButtonMetrics.iconOnlyWidth : nil)
            .frame(height: DS.Size.controlXS)
            .background(wash, in: shape)
            .background(.dsSurface, in: shape)
            .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
            .contentShape(shape)
            .fixedSize()
            .opacity(isEnabled ? 1 : 0.5)
            .dsHitTarget(DS.Size.controlXS)
            .dsFocusShape(shape)
            .trackHover($isHovered)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var wash: Color {
        guard isEnabled else { return .clear }
        if configuration.isPressed { return .dsPressed }
        if isOn { return .dsSelected }
        return isHovered ? .dsHover : .clear
    }
}

/// The glyph a size below the 12pt text, 6pt before the title; or the glyph alone, through the
/// system's icon-only style so the title stays the accessibility label.
private struct HeaderLabelStyle: LabelStyle {
    let isIconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isIconOnly {
            Label {
                configuration.title
            } icon: {
                configuration.icon
                    .font(.system(size: HeaderButtonMetrics.glyph))
            }
            .labelStyle(.iconOnly)
        } else {
            HStack(spacing: DS.Space.sm) {
                configuration.icon
                    .font(.system(size: HeaderButtonMetrics.glyph))
                configuration.title
            }
        }
    }
}

private enum HeaderButtonMetrics {
    /// Open In's halves: a 16pt icon with 6pt either side.
    static let iconOnlyWidth = DS.Size.rowLeading + 2 * DS.Space.sm
    static let glyph: CGFloat = 12
}

#Preview("Header buttons") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            Button {
            } label: {
                Label {
                    DiffStatLabel(added: 4, removed: 2)
                } icon: {
                    Image(systemName: "plus.forwardslash.minus")
                }
            }
            .buttonStyle(.header())
            Button("Show Changes", systemImage: "plus.forwardslash.minus") {}
                .buttonStyle(.header(isOn: true))
            Button("Show Terminal", systemImage: "apple.terminal") {}
                .buttonStyle(.header(iconOnly: true))
            Button("Hide Terminal", systemImage: "apple.terminal") {}
                .buttonStyle(.header(isOn: true, iconOnly: true))
            Button("Show Terminal", systemImage: "apple.terminal") {}
                .buttonStyle(.header(iconOnly: true))
                .disabled(true)
        }
        .padding(DS.Space.xl)
    }
}
