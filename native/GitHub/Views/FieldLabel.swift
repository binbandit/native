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
