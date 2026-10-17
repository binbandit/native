import SwiftUI

/// One of the home page's big buttons (the reference app's quick-action card): a glyph in the top-left
/// corner, the label at the bottom, and room top-right for a shortcut hint or progress.
///
/// the reference app fills the card with `bg-secondary`, a shade off the background toward the foreground
/// in both appearances, which `dsSurfaceSunken` matches, and outlines it with its `border`, which is
/// `dsSeparator`. Hover uses Native's wash instead of the reference app's barely visible 80% fill, so the
/// cards answer the pointer like every other control here.
struct HomeActionCard<Accessory: View>: View {
    let title: String
    let systemImage: String
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
        detail: String? = nil,
        isDetailUrgent: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.isDetailUrgent = isDetailUrgent
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: DS.Space.md) {
                    Image(systemName: systemImage)
                        .font(HomeLayout.cardGlyph)
                        .frame(width: HomeLayout.cardGlyphSlot, height: HomeLayout.cardGlyphSlot)
                    Spacer(minLength: 0)
                    accessory
                }
                Spacer(minLength: DS.Space.md)
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
            .foregroundStyle(isEnabled ? .dsTextPrimary : .dsTextTertiary)
            .padding(HomeLayout.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(HomeCardButtonStyle(isHovered: isHovered && isEnabled))
        .trackHover($isHovered)
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
            .contentShape(.focusEffect, shape)
    }
}
