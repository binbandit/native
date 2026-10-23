import SwiftUI

/// No organization name is available in policy yet; don't invent the administrator's identity.
struct CelebrationOfflineNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: "wifi.slash").font(.system(size: CelebrationMetrics.offlineGlyph)).foregroundStyle(
                .dsTextTertiary)
            Text("This install can't download celebration icons. Home still dresses up on the days you choose.")
                .settingsText(.body).foregroundStyle(.dsTextSecondary)
        }
    }
}

#if DEBUG
#Preview("Celebrations - Offline notice") {
    DSPreviewPair { CelebrationOfflineNotice().settingsPreviewPage() }
}
#endif
