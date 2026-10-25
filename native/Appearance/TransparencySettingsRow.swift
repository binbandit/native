import SwiftUI

struct TransparencySettingsRow: View {
    var reduceTransparencyOverride: Bool?
    static let rowID = SettingsRowID("appearance.transparency")
    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID, title: "Transparency", description: "How much shows through the window.",
            keywords: ["translucent", "glass", "blur", "opaque", "solid", "sidebar"])
    }
    @AppStorage(AppearancePreferences.transparencyKey) private var transparency = DSTransparency.standard
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        SettingsRow(id: Self.rowID, "Transparency") {
            SettingsSelect(
                label: "Transparency", selection: $transparency,
                options: DSTransparency.allCases.map { .init(value: $0, title: $0.title) },
                isDefault: transparency == .standard
            )
            .disabled(reduceTransparencyOverride ?? reduceTransparency)
        }
    }

    static var reduceTransparencyNote: String {
        #if os(macOS)
        "Your Mac's Reduce Transparency setting is on, so Native stays solid. You can change it in System Settings > Accessibility > Display."
        #else
        "Your iPad's Reduce Transparency setting is on, so Native stays solid. You can change it in Settings > Accessibility > Display & Text Size."
        #endif
    }
}

#if DEBUG
#Preview("Appearance - Reduce Transparency") {
    DSPreviewPair {
        SettingsRowGroup { TransparencySettingsRow(reduceTransparencyOverride: true) }.settingsPreviewPage()
    }
    .environment(\.settingsPlainly, true)
    .defaultAppStorage(PreviewUserDefaults())
}
#endif
