import AppAppearance
import Foundation
import Observation

/// The celebrations the phone can put on its icon: Native's catalogue and overlap policy
/// (`Packages/AppAppearance`, `docs/celebrations.md`) with the same chooser model as the Mac, every
/// celebration off until picked and shown on its dates. The phone keeps its own choices, and it has
/// no Home page, so only the icon counts. Each edition's icon is the flat one this build bundles.
@Observable
final class CompanionCelebrations {
    private(set) var preferences: CelebrationPreferences
    let catalog: AppearanceCatalog

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "celebrations"

    init(defaults: UserDefaults = .standard, bundled: Set<String> = BundledAppIcons.names) {
        self.defaults = defaults
        preferences =
            defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(CelebrationPreferences.self, from: $0) }
            ?? CelebrationPreferences()
        catalog = AppearanceCatalog([
            AppearanceCatalog.Plugin(
                source: Self.source(bundled: bundled),
                iconSets: ContributionList(FirstPartyCelebrations.iconSets),
                celebrations: ContributionList(FirstPartyCelebrations.celebrations))
        ])
    }

    var events: [CelebrationEvent] { catalog.celebrations }

    var enabledCount: Int {
        events.count { preferences.selection(for: $0.id).isEnabled }
    }

    func selection(for event: CelebrationEvent) -> CelebrationPreferences.Selection {
        preferences.selection(for: event.id)
    }

    func setEnabled(_ isEnabled: Bool, for event: CelebrationEvent) {
        preferences.setEnabled(isEnabled, for: event.id)
        save()
    }

    func setStyle(_ style: IconSetID, for event: CelebrationEvent) {
        preferences.selections[event.id, default: .init()].style = style == event.styles.first?.id ? nil : style
        save()
    }

    /// The celebration showing on `day`, if one is: its event in the chosen style, the occurrence,
    /// and the icon to show.
    func active(on day: CivilDate) -> (event: CelebrationEvent, occurrence: CelebrationOccurrence, iconName: String)? {
        guard let active = resolution(on: day).active, active.appliesToAppIcon,
            let event = catalog.celebration(active.eventID).map(preferences.styled),
            let set = event.iconSet
        else { return nil }
        return (event, active.occurrence, Self.iconName(for: set.id))
    }

    func nextOccurrence(of event: CelebrationEvent, from day: CivilDate) -> CelebrationOccurrence? {
        event.nextOccurrence(window: preferences.selection(for: event.id).window, from: day)
    }

    /// The bundled icon for an icon set: `native.dia-de-muertos` is `AppIcon-dia-de-muertos`.
    static func iconName(for set: IconSetID) -> String {
        let edition = set.rawValue.hasPrefix("native.") ? String(set.rawValue.dropFirst("native.".count)) : set.rawValue
        return "AppIcon-\(edition)"
    }

    private func resolution(on day: CivilDate) -> CelebrationResolution {
        // Home isn't a surface here, so a celebration only wins when it changes the icon.
        var iconOnly = preferences
        for id in iconOnly.selections.keys { iconOnly.selections[id]?.home = false }
        return CelebrationPolicy.resolve(events, preferences: iconOnly, on: day)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: Self.key)
    }

    /// Native's own sets, with every edition's icon ready when this build bundles it: the engine's
    /// four channels all name the one flat Regular icon, since the phone has no channels.
    private static func source(bundled: Set<String>) -> ContributionSource {
        ContributionSource(
            pluginID: "native.celebrations", location: .builtIn,
            // Halloween names compiled images per channel and appearance; on the phone they're its one icon.
            assetExists: { $0.hasPrefix("AppIcon-halloween-") && bundled.contains("AppIcon-halloween") },
            packState: { edition in
                let name = "AppIcon-\(edition)"
                guard bundled.contains(name) else { return .unavailable("This version of the app doesn't include it.") }
                let pair = AppIconImagePair(light: .asset(name), dark: .asset(name))
                return .ready(Dictionary(uniqueKeysWithValues: AppIconVariant.allCases.map { ($0, pair) }))
            })
    }
}
