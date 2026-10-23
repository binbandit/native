import SwiftUI

/// A named group with its help directly underneath, matching the Mac's Settings grammar.
struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(title)
                .font(DS.Settings.groupTitle)
                .foregroundStyle(.dsTextPrimary)
                .padding(.leading, DS.Space.xxs)
                .accessibilityAddTraits(.isHeader)
            SettingsRowGroup { content }
            if let footer { SettingsFooter(footer) }
        }
    }
}

#if DEBUG
#Preview("Plainly - Group") {
    DSPreviewPair {
        SettingsGroup(title: "Dock") {
            SettingsRow("Badge") { SettingsValue("Tasks that need you") }
        }
        .settingsPreviewPage()
    }
    .environment(\.settingsPlainly, true)
}
#endif
