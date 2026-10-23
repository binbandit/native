import SwiftUI

/// One setting: a medium title with optional accessories, a muted description and smaller detail,
/// and the control on the right. Rows with a detail line pin the control to the top, so it lines up
/// with the title.
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
    var plainly: SettingsPlainlyCopy?
    /// An SF Symbol shown in a tile before the text, for rows that stand for a thing (an agent, a server).
    var icon: String?
    var description: Text?
    var detail: Text?
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var control: Control

    @Environment(\.settingsPlainly) private var usesPlainly

    @Environment(\.settingsLockReason) private var lockReason
    @Environment(\.settingsControlBelow) private var isControlBelow

    var body: some View {
        Group {
            if isControlBelow {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    label
                    trailing
                }
            } else if usesPlainly {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SettingsMetrics.rowControlSpacing) {
                        label.frame(minWidth: DS.Settings.rowLabelMinWidth)
                        trailing
                    }
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        label
                        trailing
                    }
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
                    (usesPlainly ? plainly.map { Text($0.title) } ?? title : title)
                        .settingsText(usesPlainly ? .body : .bodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    accessory
                    if let lockReason {
                        SettingsBadge(lockReason, systemImage: "lock.fill")
                    }
                }
                // The line takes the text column's width. Sized to its own, it was laid out again a
                // fraction narrower beside a wider description, truncating its last accessory and
                // centering in the leftover ("node_repl" on MCP Servers).
                .frame(
                    maxWidth: .infinity,
                    minHeight: usesPlainly
                        ? DS.Settings.rowTitleHeight : SettingsMetrics.rowTitleHeight,
                    alignment: .leading)
                if let description = usesPlainly && plainly != nil && plainly?.preservesDescription != true
                    ? plainly?.description.map(Text.init) : description
                {
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

    /// The control, dimmed and explained while the organization (or something else) locks it. A
    /// button here is an action, so one without a style of its own gets the settings button.
    private var trailing: some View {
        control
            .environment(\.settingsRowTitle, usesPlainly ? plainly?.title : nil)
            .buttonStyle(.settings)
            // Beside the text a control keeps its own width; under it, it may take the row's.
            .fixedSize(horizontal: !isControlBelow && !usesPlainly, vertical: true)
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
        plainly: SettingsPlainlyCopy? = nil,
        icon: String? = nil,
        description: Text? = nil,
        detail: Text? = nil,
        @ViewBuilder control: () -> Control
    ) {
        self.init(
            id: id, title: Text(title), plainly: plainly, icon: icon, description: description, detail: detail,
            accessory: { EmptyView() }, control: control)
    }
}

extension SettingsRow where Control == EmptyView {
    @available(*, unavailable, message: "Information goes in a SettingsNote, and a value in SettingsValue")
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
    @available(*, unavailable, message: "Information goes in a SettingsNote, and a value in SettingsValue")
    init(
        id: SettingsRowID? = nil,
        _ title: String,
        plainly: SettingsPlainlyCopy? = nil,
        icon: String? = nil,
        description: Text? = nil,
        detail: Text? = nil,
        @ViewBuilder control: () -> Control
    ) {
        fatalError("unavailable")
    }
}

/// Rows with a hairline between each (every row but the first gets a top border with
/// 20pt either side).
struct SettingsRowGroup<Content: View>: View {
    @Environment(\.settingsPlainly) private var plainly
    @ViewBuilder var content: Content

    var body: some View {
        Group(subviews: content) { rows in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        SeparatorLine()
                            .padding(.vertical, plainly ? 0 : SettingsMetrics.rowSpacing)
                            .padding(.leading, plainly ? DS.Settings.rowInset : 0)
                    }
                    row
                        .padding(.horizontal, plainly ? DS.Settings.rowInset : 0)
                        .padding(.vertical, plainly ? DS.Settings.rowVerticalInset : 0)
                }
            }
            .background(
                plainly ? Color.dsSurface : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.panel)
            )
            .overlay {
                if plainly {
                    RoundedRectangle(cornerRadius: DS.Radius.panel)
                        .strokeBorder(.dsSeparator, lineWidth: DS.Settings.hairline)
                }
            }
        }
    }
}

/// A bordered 40pt tile with an 8pt radius on the sunken fill, holding a glyph or an icon.
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

/// An outlined tag beside a row title: where a setting comes from ("Managed", "Local") or its state.
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

#if DEBUG
#Preview("Settings rows") {
    DSPreviewPair {
        SettingsRowGroup {
            SettingsRow("Play sounds", description: Text("When a task finishes or needs you.")) {
                SettingsSwitch("Play sounds", isOn: .constant(true))
            }
            SettingsRow(
                "Follow-up behavior",
                description: Text("Queue messages to send after the agent finishes, or steer the agent mid-turn."),
                detail: Text("Agents that can't steer queue instead.")
            ) {
                SettingsSelect(
                    label: "Follow-up behavior", selection: .constant(FollowUpBehavior.queue),
                    options: FollowUpBehavior.allCases.map { .init(value: $0, title: $0.title) })
            }
            SettingsRow(
                title: Text("Codex"), icon: "terminal",
                description: Text("npx --yes @agentclientprotocol/codex-acp@2.2.2")
            ) {
                SettingsBadge("Needs sign-in", systemImage: "person.crop.circle.badge.exclamationmark")
            } control: {
                SettingsSwitch("Codex", isOn: .constant(true))
            }
            SettingsRow("Send crash reports", description: Text("Your organization decides this.")) {
                SettingsSwitch("Send crash reports", isOn: .constant(false))
            }
            .settingsLocked("Managed by your organization")
            SettingsRow("Clear the task cache") {
                Button("Clear…") {}
                    .buttonStyle(.settings)
            }
        }
        .settingsPreviewPage()
    }
}

#Preview("Plainly - Narrow rows and long values") {
    DSPreviewPair {
        SettingsRowGroup {
            SettingsRow("Model", description: Text("Start one task to see its models.")) {
                SettingsSelect(
                    label: "Model", selection: .constant("default"),
                    options: [.init(value: "default", title: "Last used (A model with a long name)")],
                    width: DS.Settings.wideControl)
            }
            SettingsRow("Keep agents running after you quit") {
                SettingsSwitch("Keep agents running after you quit", isOn: .constant(true))
            }
        }
        .settingsPreviewPage(width: 320)
    }
    .environment(\.settingsPlainly, true)
}
#endif
