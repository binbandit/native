import NativePolicy
import SwiftUI

/// The lock remains an actionable explanation, including when keyboard focus reaches the row.
struct AppearancePolicyDetails: View {
    let policy: NativePolicy
    @State private var copied = false
    private var organization: String { policy.organizationName ?? "your organization" }
    private var reason: String {
        policy.appearanceCodeThemeReason ?? "\(organization) sets this on every Mac it manages."
    }
    private var contact: String {
        policy.organizationContact.map { "To change it, ask in \($0)." } ?? "To change it, ask your organization."
    }
    private var details: String {
        "Set by \(organization)\n\(reason)\nSetting: policy.appearance.codeTheme\nValue: \(policy.appearanceCodeTheme ?? "native")\n\(contact)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Label("Set by \(organization)", systemImage: "building.2")
                .font(.dsCalloutMedium)
            Text(reason).font(.dsBody).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: DS.Space.md) {
                detailRow("Setting", value: "policy.appearance.codeTheme")
                detailRow("Value", value: policy.appearanceCodeTheme ?? "native")
            }
            HStack(alignment: .center, spacing: DS.Space.lg) {
                Text(contact).font(.dsBody).foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(copied ? "Copied" : "Copy Details") {
                    DSPasteboard.copy(details)
                    copied = true
                }
                .buttonStyle(.settings)
            }
        }
        .foregroundStyle(.dsTextPrimary)
        .padding(DS.Space.xl)
        .frame(width: DS.Appearance.lockWidth)
    }
    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.lg) {
            Text(title).font(.dsBody).foregroundStyle(.dsTextTertiary)
            Text(value).font(.dsMonoCaption)
        }
    }

}

#if DEBUG
#Preview("Appearance - Policy details") {
    DSPreviewPair { AppearancePolicyDetails(policy: AppearancePreviewFixtures.policy) }
}
#endif
