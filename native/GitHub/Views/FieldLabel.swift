import SwiftUI

/// A small label above a form field.
struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.dsBodyMedium)
            .foregroundStyle(.dsTextSecondary)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Field label") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            FieldLabel("Title")
            FieldLabel("Description")
        }
    }
}
#endif
