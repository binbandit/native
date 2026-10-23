#if DEBUG
import AppAppearance
import SwiftUI

/// Inert catalogue fixtures: no timers, downloads or persisted choices.
enum CelebrationPreviewFixtures {
    enum State: String, CaseIterable {
        case off, menu, style, page, showing, homeOnly, skipped, waiting, failed, empty, yearHover, rows, overlaps,
            detail, offline,
            confirmation
    }

    static func center(_ state: State = .page) -> CelebrationCenter {
        let day = CivilDate("2026-10-23") ?? CivilDate(dayNumber: 20749)
        let center = CelebrationCenter(
            defaults: PreviewUserDefaults(), runsEffects: false,
            now: { day.start(in: .current) })
        if state == .off { return center }
        let catalogue = AppearanceCatalog([
            .init(
                source: ContributionSource(
                    pluginID: CelebrationsPlugin.id, location: .builtIn,
                    assetExists: PlatformAppIcon.hasAsset(named:), homeMarks: HomeLandingEdition.drawableMarks,
                    packState: { edition in
                        switch state {
                        case .offline, .homeOnly: return .unavailable("This install can't download icons.")
                        case .waiting: return .downloading
                        case .failed: return .failed("The download couldn't finish. Try again when you're connected.")
                        default:
                            let pair = AppIconImagePair(
                                light: .asset("CelebrationThumbnail-\(edition)-light"),
                                dark: .asset("CelebrationThumbnail-\(edition)-dark"))
                            return .ready(Dictionary(uniqueKeysWithValues: AppIconVariant.allCases.map { ($0, pair) }))
                        }
                    }), iconSets: IconSetContributions(FirstPartyCelebrations.iconSets),
                celebrations: CelebrationContributions(FirstPartyCelebrations.celebrations))
        ])
        center.update(catalog: catalogue)
        if state != .empty {
            let ids = [
                "halloween", "dia-de-muertos", "diwali", "hanukkah", "christmas", "kwanzaa", "new-year",
                "spring-festival", "mathematics-day", "programmers-day",
            ]
            for id in ids { center.setAutomatic(true, for: CelebrationID("native.\(id)")) }
        }
        if state == .waiting || state == .failed {
            center.setHome(false, for: FirstPartyCelebrations.halloweenID)
        }
        if state == .rows || state == .style { center.setAutomatic(true, for: CelebrationID("native.australia-day")) }
        if state == .skipped { center.restoreBase() }
        return center
    }

    static func registry(_ state: State = .page) -> PluginRegistry {
        let defaults = PreviewUserDefaults()
        defaults.set([CelebrationsPlugin.id: state != .off], forKey: "pluginChoices")
        return PluginRegistry(builtIns: [CelebrationsPlugin()], defaults: defaults)
    }
}
#endif
