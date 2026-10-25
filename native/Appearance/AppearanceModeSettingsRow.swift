import SwiftUI

struct AppearanceModeSettingsRow: View {
    static let rowID = SettingsRowID("appearance.mode")
    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Appearance", description: "Auto, light or dark.",
            keywords: ["system", "automatic", "auto", "light", "dark", "theme"])
    }

    @Environment(AppearanceModeController.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        SettingsRow(id: Self.rowID, "Appearance") {
            Picker("Appearance", selection: $appearance.mode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: DS.Settings.wideControl)
        }
    }
}

#if DEBUG
#Preview("Appearance - Auto, Light and Dark") {
    DSPreviewPair { SettingsRowGroup { AppearanceModeSettingsRow() }.settingsPreviewPage() }
        .environment(AppearanceModeController(defaults: PreviewUserDefaults()))
        .environment(\.settingsPlainly, true)
}
#endif
