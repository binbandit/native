import SwiftUI

/// The terminal owns whether it follows Appearance's code font; the stored preference stays the same.
struct TerminalCodeFontRow: View {
    static let rowID = SettingsRowID("terminal.code-font")
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(
            id: Self.rowID, "Use the same font as code", description: Text("Use the font and size from Appearance.")
        ) {
            SettingsSwitch("Use the same font as code", isOn: $isOn)
        }
    }
}

#if DEBUG
#Preview("Terminal - Follow code font on and off") {
    DSPreviewPair {
        SettingsRowGroup {
            TerminalCodeFontRow(isOn: .constant(true))
            TerminalCodeFontRow(isOn: .constant(false))
        }
        .settingsPreviewPage()
    }
    .environment(\.settingsPlainly, true)
}
#endif
