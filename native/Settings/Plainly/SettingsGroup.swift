import SwiftUI

/// A named group with its help directly underneath, matching the Mac's Settings grammar.
struct SettingsGroup<Content: View, Accessory: View, FooterAccessory: View>: View {
    let title: String
    var footer: String?
    /// Trailing the title, such as a column header for the rows below.
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    /// Under the footer, such as a link to where the group's settings are edited.
    @ViewBuilder var footerAccessory: FooterAccessory

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(DS.Settings.groupTitle)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Space.md)
                accessory
            }
            .padding(.leading, DS.Space.xxs)
            SettingsRowGroup { content }
            if let footer { SettingsFooter(footer) }
            footerAccessory.padding(.horizontal, DS.Settings.rowInset)
        }
    }
}

extension SettingsGroup where FooterAccessory == EmptyView {
    init(
        title: String, footer: String? = nil, @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title, footer: footer, accessory: accessory, content: content,
            footerAccessory: {
                EmptyView()
            })
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(
        title: String, footer: String? = nil, @ViewBuilder content: () -> Content,
        @ViewBuilder footerAccessory: () -> FooterAccessory
    ) {
        self.init(
            title: title, footer: footer, accessory: { EmptyView() }, content: content,
            footerAccessory: footerAccessory)
    }
}

extension SettingsGroup where Accessory == EmptyView, FooterAccessory == EmptyView {
    init(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(
            title: title, footer: footer, accessory: { EmptyView() }, content: content,
            footerAccessory: {
                EmptyView()
            })
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
