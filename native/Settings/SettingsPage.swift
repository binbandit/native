import SwiftUI

/// The body of a settings page: its header and row groups 24pt apart, no wider than Conductor's
/// `max-w-4xl`.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            content
        }
        .frame(maxWidth: SettingsMetrics.pageMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A page's title with an optional description below and actions on the right.
struct SettingsHeader<Actions: View>: View {
    let title: String
    var description: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text(title)
                    .settingsText(.title)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let description {
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
    init(_ title: String, description: Text? = nil) {
        self.init(title: title, description: description) { EmptyView() }
    }
}

/// A heading over part of a page. It's a step larger than a row title, in the primary color, with
/// extra room above, so it reads as the start of a section rather than a dimmed row; the note under
/// it is the section's description.
struct SettingsSubheading: View {
    let title: String
    var note: String?

    init(_ title: String, note: String? = nil) {
        self.title = title
        self.note = note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title)
                .settingsText(.heading)
                .foregroundStyle(.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if let note {
                Text(note)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, SettingsMetrics.sectionTopInset)
    }
}
