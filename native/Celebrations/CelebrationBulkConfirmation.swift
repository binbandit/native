import SwiftUI

struct CelebrationBulkConfirmation: View {
    let summary: String
    var undo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Image(systemName: "checkmark").font(.system(size: CelebrationMetrics.factGlyph)).foregroundStyle(
                .dsTextSecondary)
            Text(summary)
                .settingsText(.body).foregroundStyle(.dsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // A native button keeps Undo reachable by keyboard and accessibility actions.
            Button(action: undo) {
                Text("Undo").underline().settingsText(.body).foregroundStyle(.dsTextPrimary)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .dsHitTarget(CelebrationMetrics.factGlyph)
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Celebrations - Confirmation") {
    DSPreviewPair { CelebrationPreviewGallery(.confirmation).settingsPreviewPage() }.environment(SettingsPresentation())
}
#endif
