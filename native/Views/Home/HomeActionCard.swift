import SwiftUI

/// One of the home page's big buttons (Conductor's quick-action card): a glyph in the top-left
/// corner, the label at the bottom, and room top-right for a shortcut hint or progress.
///
/// Conductor fills the card with `bg-secondary`, a shade off the background toward the foreground
/// in both appearances, which `dsSurfaceSunken` matches, and outlines it with its `border`, which is
/// `dsSeparator`. Hover uses Native's wash instead of Conductor's barely visible 80% fill, so the
/// cards answer the pointer like every other control here.
struct HomeActionCard<Accessory: View>: View {
    let title: String
    let systemImage: String
    /// Draws this agent's icon in place of the symbol.
    var agent: AgentDefinition?
    /// A second line under the label, such as why an agent can't start tasks.
    var detail: String?
    /// Whether the detail asks something of the user, which sets it in the attention color.
    var isDetailUrgent = false
    let action: () -> Void
    @ViewBuilder var accessory: Accessory

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    init(
        _ title: String,
        systemImage: String,
        agent: AgentDefinition? = nil,
        detail: String? = nil,
        isDetailUrgent: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.agent = agent
        self.detail = detail
        self.isDetailUrgent = isDetailUrgent
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        Button(action: action) {
            // A full-height card stacks glyph over label; a one-column grid gives each card a short
            // row, where the same parts sit side by side.
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: DS.Space.md) {
                        glyph
                        Spacer(minLength: 0)
                        accessory
                    }
                    Spacer(minLength: DS.Space.md)
                    labels
                }
                .padding(HomeLayout.cardPadding)
                HStack(spacing: DS.Space.lg) {
                    glyph
                    labels
                    Spacer(minLength: 0)
                    accessory
                }
                .padding(.horizontal, HomeLayout.cardPadding)
            }
            .foregroundStyle(isEnabled ? .dsTextPrimary : .dsTextTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(HomeCardButtonStyle(isHovered: isHovered && isEnabled))
        // The label is a layout of glyphs and text, which VoiceOver doesn't name on its own.
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? "")
        .trackHover($isHovered)
    }

    @ViewBuilder private var glyph: some View {
        if let agent {
            AgentIcon(agent: agent, style: .tile, size: HomeLayout.cardGlyphSlot)
        } else {
            Image(systemName: systemImage)
                .font(HomeLayout.cardGlyph)
                .frame(width: HomeLayout.cardGlyphSlot, height: HomeLayout.cardGlyphSlot)
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title)
                .font(.dsCallout)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.dsBody)
                    .foregroundStyle(isDetailUrgent && isEnabled ? .dsAttention : .dsTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

extension HomeActionCard where Accessory == EmptyView {
    init(_ title: String, systemImage: String, detail: String? = nil, action: @escaping () -> Void) {
        self.init(title, systemImage: systemImage, detail: detail, action: action) {
            EmptyView()
        }
    }
}

private struct HomeCardButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        configuration.label
            .background {
                shape.fill(.dsSurfaceSunken)
                shape.fill(configuration.isPressed ? .dsPressed : isHovered ? .dsHover : .clear)
            }
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
            .contentShape(shape)
            .dsFocusShape(shape)
    }
}
