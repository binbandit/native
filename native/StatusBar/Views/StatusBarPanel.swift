import SwiftUI

/// A status-bar item's details, as the reference app lays out its Resource Manager: a header with the item's
/// glyph and name and its actions on the right, a hairline, then the content.
struct StatusBarPanel<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                StatusBarGlyph(systemImage)
                    .foregroundStyle(.dsTextTertiary)
                Text(title)
                    .font(.dsCaptionMedium)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Space.md)
                accessory
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.Size.controlSM)
            SeparatorLine()
            content
        }
        .frame(width: StatusBarMetrics.panelWidth)
    }
}

extension StatusBarPanel where Accessory == EmptyView {
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, accessory: { EmptyView() }, content: content)
    }
}

/// A panel's closing note: what the numbers mean, in the tertiary caption style.
struct StatusBarPanelFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(spacing: 0) {
            SeparatorLine()
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.md)
        }
    }
}
