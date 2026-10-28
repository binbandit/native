#if DEBUG
import CodeThemes
import NativePolicy
import SwiftUI

/// Fictional, in-memory data only. No task, repository, terminal or plugin is opened.
enum AppearancePreviewFixtures {
    static let policy = PolicyLoader.load(
        from: StaticPolicySource(managed: [
            "policy.organization.name": "Northwind Federal IT",
            "policy.organization.contact": "#it-help",
            "policy.appearance.codeTheme": "native",
            "policy.appearance.codeTheme.reason": "Consistent code colors on every managed Mac.",
        ]))

    static func policyCenter(locked: Bool) -> PolicyCenter {
        PolicyCenter(
            source: StaticPolicySource(
                managed: locked
                    ? [
                        "policy.organization.name": "Northwind Federal IT",
                        "policy.organization.contact": "#it-help",
                        "policy.appearance.codeTheme": "native",
                        "policy.appearance.codeTheme.reason": "Consistent code colors on every managed Mac.",
                    ] : [:]))
    }

    static var latest: SpecimenLine {
        let sample = SpecimenLine.sample()
        return SpecimenLine.choose(from: [
            .init(
                file: sample.file, project: sample.project, language: sample.language,
                deleted: sample.deleted, added: sample.added)
        ])
    }

    static func card(
        sample: Bool = false, plugin: Bool = false, disabled: Bool = false,
        locked: Bool = false, showLock: Bool = false, width: CGFloat = 640
    ) -> some View {
        let defaults = PreviewUserDefaults()
        if plugin {
            defaults.set("lantern/dusk", forKey: AppearancePreferences.darkCodeThemeKey)
            defaults.set("lantern/linen", forKey: AppearancePreferences.lightCodeThemeKey)
        }
        let registry = PluginRegistry(
            previewing: plugin ? [AppearanceFixturePlugin()] : [],
            disabled: disabled ? ["lantern"] : [])
        let tryOn = ThemeTryOnModel(
            app: AppModel.preview(.empty), settings: SettingsPresentation(),
            appearance: AppearanceModeController(defaults: defaults), plugins: registry, defaults: defaults,
            policy: { policyCenter(locked: locked).policy })
        return DSPreviewPair {
            CodeThemeSettingsRow(
                defaults: defaults, fixedSpecimen: sample ? .sample() : latest, initiallyShowsPolicyDetails: showLock
            )
            .frame(width: width)
            .padding(DS.Space.xl)
        }
        .environment(tryOn)
        .environment(registry)
        .environment(policyCenter(locked: locked))
        .environment(SettingsPresentation())
        .environment(\.settingsPlainly, true)
    }

    static func page(locked: Bool = false, showLock: Bool = false, width: CGFloat = 640) -> some View {
        let defaults = PreviewUserDefaults()
        return DSPreviewPair {
            AppearanceSettingsContent(defaults: defaults, fixedSpecimen: latest)
                .settingsPreviewPage(width: width)
        }
        .defaultAppStorage(defaults)
        .environment(AppModel.preview(.empty))
        .environment(PluginRegistry(previewing: []))
        .environment(policyCenter(locked: locked))
        .environment(AppearanceModeController(defaults: defaults))
        .environment(AppIconPreferences(defaults: defaults))
    }

    static func window(warmAndBlack: Bool, mode: AppearanceMode = .system) -> some View {
        let defaults = PreviewUserDefaults()
        defaults.set(warmAndBlack ? "wool" : "paper", forKey: AppearancePreferences.lightToneKey)
        defaults.set(warmAndBlack ? "trueBlack" : "standard", forKey: AppearancePreferences.darkToneKey)
        defaults.set(mode.rawValue, forKey: AppearancePreferences.modeKey)
        return DSPreviewPair {
            SettingsGroup(title: "Window") {
                AppearanceModeSettingsRow()
                LightToneSettingsRow()
                DarkToneSettingsRow()
                TransparencySettingsRow()
            }
            .settingsPreviewPage(width: 640)
        }
        .environment(AppearanceModeController(defaults: defaults))
        .defaultAppStorage(defaults)
        .dsLightTone(warmAndBlack ? .wool : .paper)
        .dsDarkTone(warmAndBlack ? .trueBlack : .standard)
        .environment(\.settingsPlainly, true)
    }
}

#Preview("Appearance - Paper and Standard, Auto") {
    AppearancePreviewFixtures.window(warmAndBlack: false)
}
#Preview("Appearance - Wool and True Black, Dark") {
    AppearancePreviewFixtures.window(warmAndBlack: true, mode: .dark)
}
#Preview("Appearance - Light choice") {
    AppearancePreviewFixtures.window(warmAndBlack: false, mode: .light)
}
#Preview("Appearance - Ghostty colors") {
    DSPreviewPair {
        CodeThemeSettingsRow(defaults: PreviewUserDefaults(), fixedSpecimen: .sample(), ghosttyColors: true)
            .frame(width: 640)
    }
    .environment(PluginRegistry(previewing: []))
    .environment(AppearancePreviewFixtures.policyCenter(locked: false))
    .environment(\.settingsPlainly, true)
}
#endif
