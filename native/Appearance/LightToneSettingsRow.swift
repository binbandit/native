import SwiftUI

/// Settings ▸ Appearance ▸ Light mode: Paper or Wool, the white light mode is drawn on, with a
/// small light-mode window in each so the choice shows even while the app is dark.
struct LightToneSettingsRow: View {
    static let rowID = SettingsRowID("appearance.light-tone")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID,
            title: "Light mode",
            description: "Draw light mode on crisp Paper white or warm Wool.",
            keywords: ["paper", "wool", "white", "off-white", "warm", "cream", "background", "glare"]
        )
    }

    @AppStorage(AppearancePreferences.lightToneKey) private var lightTone = DSLightTone.paper

    var body: some View {
        let _ = DebugProbe.log.notice("LightToneRow body \(lightTone.rawValue, privacy: .public)")  // DEBUG-PROBE
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(
                id: Self.rowID,
                "Light mode",
                description: Text(
                    "Draw light mode on crisp Paper white, or on Wool, a warm off-white that’s easier on the eyes.")
            ) {
                SettingsSelect(
                    label: "Light mode",
                    selection: $lightTone,
                    options: DSLightTone.allCases.map { .init(value: $0, title: $0.title) }
                )
            }
            HStack(spacing: DS.Space.lg) {
                ForEach(DSLightTone.allCases) { tone in
                    AppearanceChoiceTile(
                        title: tone.title, isSelected: tone == lightTone,
                        accessibilityLabel: "\(tone.title) light mode"
                    ) {
                        lightTone = tone
                    } preview: {
                        AppearancePreviewWindow()
                            .environment(\.colorScheme, .light)
                            .dsLightTone(tone)
                    }
                }
            }
        }
    }
}

import OSLog  // DEBUG-PROBE
enum DebugProbe { static let log = Logger(subsystem: "Native", category: "probe") }  // DEBUG-PROBE
