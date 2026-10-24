#if DEBUG
import AppAppearance

enum CelebrationPreviewFixtures {
    static func downloadsDisabled() -> CelebrationCenter? {
        guard let today = CivilDate(year: 2026, month: 11, day: 1) else { return nil }
        let plugin = CelebrationsPlugin().manifest
        let catalog = AppearanceCatalog([
            .init(
                source: ContributionSource(
                    pluginID: plugin.id, location: .builtIn, assetExists: { _ in true },
                    homeMarks: HomeLandingEdition.drawableMarks,
                    packState: { _ in .unavailable(CelebrationAssetDownloads.disabled) }),
                iconSets: plugin.iconSets, celebrations: plugin.celebrations)
        ])
        var preferences = CelebrationPreferences()
        preferences.setEnabled(true, for: FirstPartyCelebrations.diaDeMuertosID)
        return CelebrationCenter.preview(
            catalog: catalog, preferences: preferences, today: today)
    }
}
#endif
