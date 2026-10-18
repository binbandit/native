import SwiftUI

/// One setting, laid out like Conductor's settings rows: a medium title with optional accessories,
/// a muted description and smaller detail, and the control on the right. Rows with a detail line
/// pin the control to the top, as Conductor's do, so it lines up with the title.
///
/// The trailing edge says what kind of row it is, so a glance tells them apart:
/// - a control (`SettingsSwitch`, `SettingsSelect`, a field) is a setting the user can change;
/// - an outlined button with a verb (`.buttonStyle(.settings)`) is an action;
/// - plain text (`SettingsValue`) is a value that can't be changed here;
/// - a lock badge and a dimmed control mean the organization decides (`.settingsManaged(by:)`).
///
/// Information that is none of these goes in a `SettingsNote`. A row always has something on its
/// trailing edge: one without reads as a setting that lost its control.
struct SettingsRow<Accessory: View, Control: View>: View {
    /// Where search reveals the row.
    var id: SettingsRowID?
    let title: Text
    /// An SF Symbol shown in a tile before the text (Conductor's integration cards).
    var icon: String?
    var description: Text?
    var detail: Text?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var control: Control

    @Environment(\.settingsLockReason) private var lockReason
    @Environment(\.settingsControlBelow) private var isControlBelow

    var body: some View {
        Group {
            if isControlBelow {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    label
                    trailing
                }
            } else {
                HStack(alignment: detail == nil ? .center : .top, spacing: SettingsMetrics.rowControlSpacing) {
                    label
                    trailing
                }
            }
        }
        .settingsRevealTarget(id)
    }

    private var label: some View {
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
                    if let lockReason {
                        SettingsBadge(lockReason, systemImage: "lock.fill")
                    }
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
    }

    /// The control, dimmed and explained while the organization (or something else) locks it.
    private var trailing: some View {
        control
            // Beside the text a control keeps its own width; under it, it may take the row's.
            .fixedSize(horizontal: !isControlBelow, vertical: true)
            .disabled(lockReason != nil)
            .help(lockReason ?? "")
    }
}

extension EnvironmentValues {
    /// Puts rows' controls on a line of their own under the text, for controls too wide to sit
    /// beside it (several pickers, an editor).
    @Entry var settingsControlBelow = false
}

extension View {
    /// Puts the rows' controls under their text instead of beside it.
    func settingsControlBelow() -> some View {
        environment(\.settingsControlBelow, true)
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
        self.init(
            id: id, title: Text(title), icon: icon, description: description, detail: detail,
            accessory: { EmptyView() }, control: control)
    }
}

extension SettingsRow where Control == EmptyView {
    @available(*, deprecated, message: "Information goes in a SettingsNote, and a value in SettingsValue")
    init(
        id: SettingsRowID? = nil,
        title: Text,
        icon: String? = nil,
        description: Text? = nil,
        detail: Text? = nil,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder control: () -> Control
    ) {
        fatalError("unavailable")
    }
}

extension SettingsRow where Accessory == EmptyView, Control == EmptyView {
    @available(*, deprecated, message: "Information goes in a SettingsNote, and a value in SettingsValue")
    init(
        id: SettingsRowID? = nil,
        _ title: String,
        icon: String? = nil,
        description: Text? = nil,
        detail: Text? = nil,
        @ViewBuilder control: () -> Control
    ) {
        fatalError("unavailable")
    }
}

/// Rows with a hairline between each (Conductor gives every row but the first a top border with
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

/// A bordered tile holding a glyph or an icon (Conductor `size-10 rounded-lg border bg-muted`).
struct SettingsIconTile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        content
            .font(.system(size: SettingsMetrics.tileGlyph, weight: .thin))
            .foregroundStyle(.dsTextPrimary)
            .frame(width: SettingsMetrics.iconTile, height: SettingsMetrics.iconTile)
            .background(.dsSurfaceSunken, in: shape)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

extension SettingsIconTile where Content == Image {
    init(systemImage: String) {
        self.init { Image(systemName: systemImage) }
    }
}

/// An outlined tag beside a row title (Conductor's "Managed"/"Local" source badge).
struct SettingsBadge: View {
    let text: String
    var systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        HStack(spacing: DS.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .settingsText(.caption)
        .foregroundStyle(.dsTextSecondary)
        .padding(.horizontal, DS.Space.md)
        .frame(height: SettingsMetrics.badgeHeight)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .fixedSize()
    }
}
