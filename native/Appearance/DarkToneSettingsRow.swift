import SwiftUI

struct DarkToneSettingsRow: View {
    static let rowID = SettingsRowID("appearance.dark-tone")
    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Dark background", description: "Choose the dark background.",
            keywords: ["standard", "true black", "oled"])
    }

    @AppStorage(AppearancePreferences.darkToneKey) private var tone = DSDarkTone.standard

    var body: some View {
        SettingsRow(id: Self.rowID, "Dark background") {
            SettingsSelect(
                label: "Dark background", selection: $tone,
                options: DSDarkTone.allCases.map { .init(value: $0, title: $0.title) },
                isDefault: tone == .standard,
                leading: AnyView(
                    Circle().fill(.dsBackground)
                        .overlay {
                            Circle().strokeBorder(
                                .dsBorderInner.opacity(DS.Appearance.swatchStrokeOpacity),
                                lineWidth: DS.Settings.hairline)
                        }
                        .frame(width: DS.Appearance.swatch, height: DS.Appearance.swatch)
                        .environment(\.colorScheme, .dark)
                        .dsDarkTone(tone)))
        }
    }
}

#if DEBUG
#Preview("Appearance - Dark backgrounds") {
    DSPreviewPair { SettingsRowGroup { DarkToneSettingsRow() }.settingsPreviewPage() }
        .defaultAppStorage(PreviewUserDefaults())
        .environment(\.settingsPlainly, true)
}
#endif
