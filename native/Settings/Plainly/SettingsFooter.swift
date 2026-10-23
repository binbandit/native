import SwiftUI

/// Help that applies to a whole group, kept outside its controls.
struct SettingsFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DS.Settings.caption)
            .foregroundStyle(.dsTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Settings.rowInset)
    }
}

#if DEBUG
#Preview("Settings footer") {
    DSPreviewPair {
        SettingsFooter("Closing the lid still sleeps your Mac.")
            .frame(width: DS.Settings.pageWidth)
    }
}
#endif
