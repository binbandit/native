import SwiftUI

/// Features contribute real pages; the map presents their headers as sections without copying controls.
struct SettingsCombinedPage: View {
    let panes: [SettingsPane]
    var title: String?

    var body: some View {
        SettingsPage {
            if let title { SettingsHeader(title) }
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                pane.makeContent()
                    .environment(
                        \.settingsSectionTitle,
                        index == 0 && title == nil ? nil : SettingsPageMap.sectionTitle(pane.id, fallback: pane.title)
                    )
                    .settingsRevealTarget(SettingsPageMap.sectionID(pane.id))
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var settingsPlainly = false
    @Entry var settingsSectionTitle: String?
    @Entry var settingsRowTitle: String?
}

#if DEBUG
#Preview("Plainly - Combined pages") {
    DSPreviewPair {
        SettingsCombinedPage(panes: [.general])
            .settingsPreviewPage()
    }
    .environment(SettingsPresentation())
    .environment(DockBadgePreference(defaults: PreviewUserDefaults()))
    .environment(\.settingsPlainly, true)
    .defaultAppStorage(PreviewUserDefaults())
}
#endif
