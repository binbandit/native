import SwiftUI

/// The body of a settings page: its header and row groups 24pt apart, at most 896pt wide.
struct SettingsPage<Content: View>: View {
    @Environment(\.settingsPlainly) private var plainly
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            content
        }
        .frame(maxWidth: plainly ? DS.Settings.pageWidth : SettingsMetrics.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: plainly ? .center : .leading)
    }
}

/// A page's title with an optional description below and actions on the right.
struct SettingsHeader<Actions: View>: View {
    @Environment(\.settingsPlainly) private var usesPlainly
    @Environment(\.settingsSectionTitle) private var sectionTitle
    let title: String
    var description: Text?
    var plainly: SettingsPlainlyCopy?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: usesPlainly ? DS.Space.xs : DS.Space.md) {
                Text(sectionTitle ?? (usesPlainly ? plainly?.title ?? title : title))
                    .settingsText(sectionTitle == nil ? .title : .heading)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let description = usesPlainly && plainly != nil ? plainly?.description.map(Text.init) : description {
                    description
                        .settingsText(.body)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.md) {
                actions
            }
        }
    }
}

extension SettingsHeader where Actions == EmptyView {
    init(_ title: String, description: Text? = nil, plainly: SettingsPlainlyCopy? = nil) {
        self.init(title: title, description: description, plainly: plainly) { EmptyView() }
    }
}

/// A heading over part of a page. It's a step larger than a row title, in the primary color, with
/// extra room above, so it reads as the start of a section rather than a dimmed row; the note under
/// it is the section's description.
struct SettingsSubheading: View {
    @Environment(\.settingsPlainly) private var plainly
    let title: String
    var note: String?
    var copy: SettingsPlainlyCopy?

    init(_ title: String, note: String? = nil, plainly: SettingsPlainlyCopy? = nil) {
        self.title = title
        self.note = note
        self.copy = plainly
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(plainly ? copy?.title ?? title : title)
                .settingsText(.heading)
                .foregroundStyle(.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if let note = plainly && copy != nil ? copy?.description : note {
                Text(note)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, plainly ? 0 : SettingsMetrics.sectionTopInset)
    }
}

#if DEBUG
#Preview("Settings page") {
    DSPreviewPair {
        SettingsPage {
            SettingsHeader(
                "Git", description: Text("How tasks get their own branch and folder, and what happens when they end."))
            SettingsRowGroup {
                SettingsRow("Rename branches from the task", description: Text("Until it's pushed.")) {
                    SettingsSwitch("Rename branches from the task", isOn: .constant(true))
                }
            }
            SettingsSubheading("Worktrees", note: "Each task works in a folder of its own, so tasks never collide.")
            SettingsRowGroup {
                SettingsRow("Worktree folder") { SettingsValue("~/.native/worktrees") }
            }
        }
        .settingsPreviewPage()
    }
}
#endif
