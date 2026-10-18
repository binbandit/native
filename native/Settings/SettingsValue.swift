import SwiftUI

/// A value that can't be changed here, on a row's trailing edge: plain secondary text the user can
/// select and copy, never boxed, so it doesn't read as a control (macOS's About rows). Identifiers,
/// hosts and paths are monospaced.
///
///     SettingsRow("Version") { SettingsValue("Native 1.4 (212)") }
struct SettingsValue: View {
    let text: Text
    var isMonospaced = false

    init(_ text: Text, monospaced: Bool = false) {
        self.text = text
        isMonospaced = monospaced
    }

    init(_ string: String, monospaced: Bool = false) {
        self.init(Text(verbatim: string), monospaced: monospaced)
    }

    var body: some View {
        text
            .settingsText(isMonospaced ? .mono : .body)
            .foregroundStyle(.dsTextSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(minHeight: SettingsMetrics.controlHeight)
    }
}

#Preview("Settings value") {
    DSPreviewPair {
        SettingsRowGroup {
            SettingsRow("Version", description: Text("Stable")) { SettingsValue("Native 1.4 (212)") }
            SettingsRow("Installation ID") {
                SettingsValue("f2414e10-a111-44ad-ab8b-f92906bc2b70", monospaced: true)
            }
        }
        .frame(width: 560)
        .padding(DS.Space.xl)
    }
}
