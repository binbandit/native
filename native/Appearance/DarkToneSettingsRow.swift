import SwiftUI

/// Settings ▸ Appearance ▸ Dark mode: Standard or True Black, the black dark mode is drawn on, with
/// a small dark-mode window in each so the choice shows even while the app is light.
struct DarkToneSettingsRow: View {
    static let rowID = SettingsRowID("appearance.dark-tone")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID,
            title: "Dark mode",
            description: "Draw dark mode on a deep neutral, or on True Black for OLED screens.",
            keywords: ["true black", "black", "amoled", "oled", "standard", "background", "dark"]
        )
    }

    @AppStorage(AppearancePreferences.darkToneKey) private var darkTone = DSDarkTone.standard

    var body: some View {
        // Read once here: the tiles' ForEach builds its rows after this body returns, when reading
        // `darkTone` again could still give the value before the change, leaving the old tile checked.
        let selection = darkTone
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(
                id: Self.rowID,
                "Dark mode",
                description: Text(
                    "Draw dark mode on Standard, a deep neutral, or on True Black, pure black for OLED screens.")
            ) {
                SettingsSelect(
                    label: "Dark mode",
                    selection: $darkTone,
                    options: DSDarkTone.allCases.map { .init(value: $0, title: $0.title) }
                )
            }
            HStack(spacing: DS.Space.lg) {
                ForEach(DSDarkTone.allCases) { tone in
                    AppearanceChoiceTile(
                        title: tone.title, isSelected: tone == selection,
                        accessibilityLabel: "\(tone.title) dark mode"
                    ) {
                        darkTone = tone
                    } preview: {
                        AppearancePreviewWindow()
                            .environment(\.colorScheme, .dark)
                            .dsDarkTone(tone)
                    }
                }
            }
        }
    }
}
