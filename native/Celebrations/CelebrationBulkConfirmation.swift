import SwiftUI

struct CelebrationBulkConfirmation: View {
    let summary: String
    var undo: () -> Void

    private var message: AttributedString {
        var message = AttributedString(summary + " ")
        var link = AttributedString("Undo")
        link.link = URL(string: "native:undo-celebration")
        link.underlineStyle = .single
        message.append(link)
        return message
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Image(systemName: "checkmark").font(.system(size: CelebrationMetrics.factGlyph)).foregroundStyle(
                .dsTextSecondary)
            Text(message)
                .settingsText(.body).foregroundStyle(.dsTextPrimary).tint(.dsTextPrimary)
                .environment(
                    \.openURL,
                    OpenURLAction { _ in
                        undo(); return .handled
                    })
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Celebrations - Confirmation") {
    DSPreviewPair { CelebrationPreviewGallery(.confirmation).settingsPreviewPage() }.environment(SettingsPresentation())
}
#endif
