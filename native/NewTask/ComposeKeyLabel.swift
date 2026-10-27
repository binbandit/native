import SwiftUI

/// A primary button's label on the Compose page: an optional glyph, the action, and the Return glyph
/// that says Return in the draft does the same.
struct ComposeKeyLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(title)
            Image(systemName: "return").opacity(DS.ComposeTask.keyHintOpacity).accessibilityHidden(true)
        }
    }
}

#if DEBUG
#Preview("Compose - Key labels") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            Button {
            } label: {
                ComposeKeyLabel(title: "Start")
            }.buttonStyle(.ds(.primary, size: .medium))
            Button {
            } label: {
                ComposeKeyLabel(title: "Hold for elara", systemImage: "clock")
            }
            .buttonStyle(.ds(.primary))
        }
        .padding(DS.Space.xxl)
    }
}
#endif
