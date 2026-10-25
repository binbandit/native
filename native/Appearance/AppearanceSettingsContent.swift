import CodeThemes
import NativePolicy
import SwiftUI

#if os(macOS)
import Terminal
#endif

struct AppearanceSettingsContent: View {
    var defaults: UserDefaults = .standard
    var fixedSpecimen: SpecimenLine?
    @AppStorage(AppearancePreferences.accentKey) private var accent = ""
    @Environment(PluginRegistry.self) private var plugins
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(PolicyCenter.self) private var policyCenter: PolicyCenter?
    #if os(macOS)
    @Environment(TerminalStore.self) private var terminal: TerminalStore?
    #endif

    private var policy: NativePolicy { policyCenter?.policy ?? PolicyCenter.shared.policy }
    private var ghosttyColors: Bool {
        #if os(macOS)
        if terminal?.preferences.settings.usesGhosttyConfig == true { return true }
        if let colors = terminal?.preferences.settings.colors, case .imported = colors { return true }
        #endif
        return false
    }

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Appearance", description: Text("How Native looks. Every choice here applies as you make it."))
            if policy.appearanceCodeTheme != nil {
                HStack(alignment: .top, spacing: DS.Space.md) {
                    Image(systemName: "building.2").accessibilityHidden(true)
                    Text("\(policy.organizationName ?? "Your organization") manages 1 setting on this page.")
                    Spacer(minLength: 0)
                    if let contact = policy.organizationContact { Text("Ask in \(contact)") }
                }
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup(
                title: "Window", footer: reduceTransparency ? TransparencySettingsRow.reduceTransparencyNote : nil
            ) {
                AppearanceModeSettingsRow()
                LightToneSettingsRow()
                DarkToneSettingsRow()
                TransparencySettingsRow()
            }
            CodeThemeSettingsRow(defaults: defaults, fixedSpecimen: fixedSpecimen, ghosttyColors: ghosttyColors)
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Code font").font(DS.Settings.groupTitle)
                CodeFontSettingsRow()
            }
            #if os(macOS)
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("App icon").font(DS.Settings.groupTitle)
                AppearanceSettingsView()
            }
            #endif
            // Existing optional appearance controls remain reachable below the four primary groups.
            if !accent.isEmpty || !PluginThemeCatalog(plugins).accents.isEmpty {
                SettingsRowGroup { AccentSettingsRow() }
            }
            SettingsRowGroup { PlayfulSpinnersSettingsRow() }
        }
        .environment(\.settingsPlainly, true)
    }
}

#if DEBUG
#Preview("Appearance - Page") {
    AppearancePreviewFixtures.page()
}
#Preview("Appearance - Page narrow and managed") {
    AppearancePreviewFixtures.page(locked: true, width: 396)
}
#endif
