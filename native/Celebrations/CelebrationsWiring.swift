import AppAppearance
import Foundation
import NativePolicy
import Observation

/// Connects celebrations to the rest of the app: the enabled plugins' icon sets and celebrations in,
/// the icon out to the app icon preferences, and the chooser opened when the plugin is turned on.
@MainActor
enum CelebrationsWiring {
    static func connect(
        _ center: CelebrationCenter, plugins: PluginRegistry, icons: AppIconPreferences,
        settings: SettingsPresentation
    ) {
        // Someone who had the Halloween icon on keeps it: the plugin that now provides it comes on too.
        if center.migratedHalloweenOptIn, !plugins.hasChoice(for: CelebrationsPlugin.id) {
            plugins.setEnabled(true, for: CelebrationsPlugin.id)
        }
        center.onIconChange = { [weak icons] in icons?.celebration = $0 }
        track(plugins, center: center, icons: icons, settings: settings, wasEnabled: nil)
        center.start()
    }

    /// Rebuilds the catalogue whenever plugins reload or are switched, then watches again.
    private static func track(
        _ plugins: PluginRegistry, center: CelebrationCenter, icons: AppIconPreferences,
        settings: SettingsPresentation, wasEnabled: Bool?
    ) {
        let isEnabled = plugins.isEnabled(CelebrationsPlugin.id)
        // Only the registry is read while tracking, so updating the center can't re-trigger it.
        let (catalog, names) = withObservationTracking {
            (
                catalog(from: plugins, assets: center.assets),
                Dictionary(plugins.plugins.map { ($0.id, $0.plugin.manifest.name) }) { $1 }
            )
        } onChange: {
            Task { @MainActor in
                track(plugins, center: center, icons: icons, settings: settings, wasEnabled: isEnabled)
            }
        }
        center.update(catalog: catalog)
        icons.pluginNames = names
        icons.iconSets = catalog.themes
        // Turning the plugin on opens the chooser, where every celebration starts off.
        if wasEnabled == false, isEnabled {
            settings.open(.celebrations)
        }
    }

    /// Every enabled plugin's contributions, checked against this build: compiled images, the Home
    /// marks it can draw and its version.
    static func catalog(from plugins: PluginRegistry, assets: CelebrationAssetStore? = nil) -> AppearanceCatalog {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return AppearanceCatalog(
            plugins.plugins.filter { plugins.isEnabled($0.id) }.map { loaded in
                let location: ContributionSource.Location =
                    switch loaded.source {
                    case .builtIn: .builtIn
                    case .manifest(let url): .folder(url.deletingLastPathComponent())
                    }
                return AppearanceCatalog.Plugin(
                    source: ContributionSource(
                        pluginID: loaded.id, location: location, assetExists: PlatformAppIcon.hasAsset(named:),
                        homeMarks: HomeLandingEdition.drawableMarks, nativeVersion: version,
                        packState: { assets?.state($0) ?? .notDownloaded }),
                    iconSets: loaded.plugin.manifest.iconSets,
                    celebrations: PolicyCenter.shared.policy.celebrationsEnabled
                        ? loaded.plugin.manifest.celebrations : CelebrationContributions())
            })
    }
}
