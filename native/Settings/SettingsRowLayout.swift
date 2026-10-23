import SwiftUI

/// Keep the shared layout concrete so each control type does not specialize all three row layouts.
/// The facade erases only the fixed accessory and control slots, preserving their view identity.
struct SettingsRowLayout: View {
    let id: SettingsRowID?
    let title: Text
    let plainly: SettingsPlainlyCopy?
    let icon: String?
    let description: Text?
    let detail: Text?
    let accessory: AnyView
    let control: AnyView

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
                        label.frame(
                            minWidth: DS.Settings.rowLabelMinWidth,
                            idealWidth: DS.Settings.rowLabelMinWidth)
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
