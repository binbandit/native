import SwiftUI

/// Settings ▸ Appearance ▸ Transparency: how much shows through the sidebar, popovers and the
/// composer, with a preview of all three at the chosen level.
struct TransparencySettingsRow: View {
    static let rowID = SettingsRowID("appearance.transparency")

    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: rowID,
            title: "Transparency",
            description: "How much shows through the sidebar, popovers and the composer.",
            keywords: ["translucent", "translucency", "glass", "blur", "opaque", "solid", "vibrancy", "sidebar"]
        )
    }

    @AppStorage(AppearancePreferences.transparencyKey) private var transparency = DSTransparency.standard
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(
                id: Self.rowID,
                "Transparency",
                description: Text("How much of your desktop and work shows through the sidebar, popovers and the composer."),
                detail: reduceTransparency ? Text(Self.reduceTransparencyNote) : nil
            ) {
                SettingsSelect(
                    label: "Transparency",
                    selection: $transparency,
                    options: DSTransparency.allCases.map { .init(value: $0, title: $0.title) }
                )
                .disabled(reduceTransparency)
            }
            TransparencyPreview()
        }
    }

    /// The system setting wins, so say so rather than let the choice look broken.
    private static var reduceTransparencyNote: String {
        #if os(macOS)
        "Your Mac’s Reduce Transparency setting is on, so Native stays solid. You can change it in System Settings ▸ Accessibility ▸ Display."
        #else
        "Your iPad’s Reduce Transparency setting is on, so Native stays solid. You can change it in Settings ▸ Accessibility ▸ Display & Text Size."
        #endif
    }
}
