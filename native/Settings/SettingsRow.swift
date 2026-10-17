import SwiftUI

/// One setting, laid out like the reference app's settings rows: a medium title with optional accessories,
/// a muted description and smaller detail, and the control on the right. Rows with a detail line
/// pin the control to the top, as the reference app's do, so it lines up with the title.
struct SettingsRow<Accessory: View, Control: View>: View {
    /// Where search reveals the row.
    var id: SettingsRowID?
    let title: Text
    /// An SF Symbol shown in a tile before the text (the reference app's integration cards).
    var icon: String?
    var description: Text?
    var detail: Text?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: detail == nil ? .center : .top, spacing: SettingsMetrics.rowControlSpacing) {
            HStack(spacing: DS.Space.lg) {
                if let icon {
                    SettingsIconTile(systemImage: icon)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DS.Space.md) {
                        title
                            .settingsText(.bodyMedium)
                            .foregroundStyle(.dsTextPrimary)
                        accessory
                    }
                    .frame(minHeight: SettingsMetrics.rowTitleHeight)
                    if let description {
                        description
                            .settingsText(.body)
                            .foregroundStyle(.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DS.Space.xxs)
                    }
                    if let detail {
                        detail
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, DS.Space.xs)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            control
                .fixedSize()
        }
        .settingsRevealTarget(id)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(
        id: SettingsRowID? = nil,
        _ title: String,
        icon: String? = nil,
        description: Text? = nil,
        detail: Text? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.init(id: id, title: Text(title), icon: icon, description: description, detail: detail, accessory: { EmptyView() }, control: control)
    }
}

/// Rows with a hairline between each (the reference app gives every row but the first a top border with
/// 20pt either side).
struct SettingsRowGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { rows in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SeparatorLine()
                            .padding(.vertical, SettingsMetrics.rowSpacing)
                    }
                    row
                }
            }
        }
    }
}

/// A bordered tile holding a glyph (the reference app `size-10 rounded-lg border bg-muted`).
struct SettingsIconTile: View {
    let systemImage: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: SettingsMetrics.tileGlyph, weight: .thin))
            .foregroundStyle(.dsTextPrimary)
            .frame(width: SettingsMetrics.iconTile, height: SettingsMetrics.iconTile)
            .background(.dsSurfaceSunken, in: shape)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// An outlined tag beside a row title (the reference app's "Managed"/"Local" source badge).
struct SettingsBadge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Text(text)
            .settingsText(.caption)
            .foregroundStyle(.dsTextSecondary)
            .padding(.horizontal, DS.Space.md)
            .frame(height: SettingsMetrics.badgeHeight)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
            .fixedSize()
    }
}
