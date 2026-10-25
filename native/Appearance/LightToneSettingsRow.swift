import SwiftUI

struct LightToneSettingsRow: View {
    static let rowID = SettingsRowID("appearance.light-tone")
    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Light background", description: "Choose the light background.",
            keywords: ["paper", "wool", "white", "warm"])
    }

    @AppStorage(AppearancePreferences.lightToneKey) private var tone = DSLightTone.paper

    var body: some View {
        SettingsRow(id: Self.rowID, "Light background") {
            SettingsSelect(
                label: "Light background", selection: $tone,
                options: DSLightTone.allCases.map { .init(value: $0, title: $0.title) },
                isDefault: tone == .paper,
                leading: AnyView(
                    Circle().fill(.dsBackground)
                        .overlay {
                            Circle().strokeBorder(
                                .dsBorderInner.opacity(DS.Appearance.swatchStrokeOpacity),
                                lineWidth: DS.Settings.hairline)
                        }
                        .frame(width: DS.Appearance.swatch, height: DS.Appearance.swatch)
                        .environment(\.colorScheme, .light)
                        .dsLightTone(tone)))
        }
    }
}

#if DEBUG
#Preview("Appearance - Light backgrounds") {
    DSPreviewPair { SettingsRowGroup { LightToneSettingsRow() }.settingsPreviewPage() }
        .defaultAppStorage(PreviewUserDefaults())
        .environment(\.settingsPlainly, true)
}
#endif
