import SwiftUI

/// Names the administrator only when policy supplies an identity.
struct CelebrationOfflineNotice: View {
    var organizationName: String?

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "wifi.slash").font(.system(size: CelebrationMetrics.offlineGlyph)).foregroundStyle(
                .dsTextTertiary)
            Group {
                if let organizationName {
                    Text(
                        "\(Text(organizationName).font(SettingsTextStyle.bodyMedium.font).foregroundStyle(.dsTextPrimary)) installed Native without internet access, so celebration icons can't download. Home still dresses up on the days you choose."
                    )
                } else {
                    Text("This install can't download celebration icons. Home still dresses up on the days you choose.")
                }
            }
            .settingsText(.body).foregroundStyle(.dsTextSecondary)
        }
    }
}

#if DEBUG
#Preview("Celebrations - Offline notice") {
    DSPreviewPair { CelebrationOfflineNotice().settingsPreviewPage() }
}
#endif
