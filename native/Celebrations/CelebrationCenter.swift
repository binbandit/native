import AppAppearance
import Foundation
import Observation

/// Native's celebrations at runtime: the catalogue from enabled plugins, the user's choices, and the
/// one celebration in effect today, which drives both the app icon and Home. It recomputes at each
/// boundary and whenever "today" may have moved (midnight, time zone, clock, wake, activation), and
/// every change the chooser makes goes through a method here.
@MainActor
@Observable
final class CelebrationCenter {
    private(set) var catalog = AppearanceCatalog()
    private(set) var preferences: CelebrationPreferences
    private(set) var today: CivilDate
    private(set) var resolution: CelebrationResolution

    /// Whether this launch carried over the app icon's old Halloween switch, so the plugin can be
    /// turned on for someone who already had Halloween.
    @ObservationIgnored private(set) var migratedHalloweenOptIn = false
    /// Hands the icon over when it changes.
    @ObservationIgnored var onIconChange: ((AppIconCelebration?) -> Void)?

    /// Native's own icons that download when chosen.
    @ObservationIgnored let assets: CelebrationAssetStore
    @ObservationIgnored let variant: AppIconVariant
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let timeZone: () -> TimeZone
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var calendarEvents: PlatformCalendarEvents?

    private static let preferencesKey = "celebrationPreferences"
    private static let legacyHalloweenKey = "appIconHalloweenEnabled"
    /// How far "Coming up" looks ahead.
    static let horizon = 60

    init(
        defaults: UserDefaults = .standard, variant: AppIconVariant = .current,
        assets: CelebrationAssetStore = CelebrationAssetStore(),
        now: @escaping () -> Date = Date.init, timeZone: @escaping () -> TimeZone = { .current }
    ) {
        self.defaults = defaults
        self.assets = assets
        self.variant = variant
        self.now = now
        self.timeZone = timeZone
        let preferences: CelebrationPreferences
        if let data = defaults.data(forKey: Self.preferencesKey),
            let stored = try? JSONDecoder().decode(CelebrationPreferences.self, from: data)
        {
            preferences = stored
        } else {
            // The app icon's Halloween switch becomes Halloween's selection, once.
            let legacy = defaults.bool(forKey: Self.legacyHalloweenKey)
            preferences = .migrating(legacyHalloweenEnabled: legacy)
            migratedHalloweenOptIn = legacy
            defaults.removeObject(forKey: Self.legacyHalloweenKey)
        }
        self.preferences = preferences
        let today = CivilDate(now(), in: timeZone())
        self.today = today
        resolution = CelebrationPolicy.resolve([], preferences: preferences, on: today)
        save()
    }

    func start() {
        guard calendarEvents == nil else { return }
        calendarEvents = PlatformCalendarEvents { [weak self] in self?.refresh() }
        refresh()
    }

    /// The enabled plugins' icon sets and celebrations changed.
    func update(catalog: AppearanceCatalog) {
        guard catalog != self.catalog else { return }
        self.catalog = catalog
        refresh()
    }

    /// Recomputes today's celebration and schedules the next boundary.
    func refresh() {
        let date = now()
        let zone = timeZone()
        today = CivilDate(date, in: zone)
        var pruned = preferences
        pruned.prune(before: today)
        if pruned != preferences { preferences = pruned }
        resolution = CelebrationPolicy.resolve(
            catalog.celebrations, preferences: preferences, on: today, canApplyAppIcon: PlatformAppIcon.canApplyAnyImage
        )
        timer?.invalidate()
        timer = resolution.nextChange.map { boundary in
            // Relative to `now()`, which may be shifted by `-nativeDate`; the wake and clock events
            // catch a timer that sleeps through its boundary.
            Timer.scheduledTimer(
                withTimeInterval: max(1, boundary.start(in: zone).timeIntervalSince(date)), repeats: false
            ) {
                [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        }
        onIconChange?(icon)
        // Packs for celebrations coming up this week, if a choice made earlier hasn't fetched them.
        for pack in CelebrationAssets.packsDue(catalog.celebrations, preferences: preferences, on: today) {
            assets.fetch(pack)
        }
    }

    // MARK: - What's showing

    var activeEvent: CelebrationEvent? {
        resolution.active.flatMap { catalog.celebration($0.eventID) }
    }

    /// What Home draws today, or nil for the everyday mark.
    var homeLook: HomeLook? {
        guard resolution.active?.appliesToHome == true else { return nil }
        return activeEvent?.homeLook
    }

    /// The name Home announces with its look.
    var homeTitle: String? {
        homeLook == nil ? nil : activeEvent?.contribution.title.resolved()
    }

    var icon: AppIconCelebration? {
        guard resolution.active?.appliesToAppIcon == true, let event = activeEvent,
            let icons = event.iconSet?.icons[variant]
        else { return nil }
        return AppIconCelebration(title: event.contribution.title.resolved(), icons: icons)
    }

    func schedule(days: Int = horizon) -> [CelebrationScheduleSegment] {
        CelebrationPolicy.schedule(
            catalog.celebrations, preferences: preferences, from: today, through: today.adding(days: days),
            canApplyAppIcon: PlatformAppIcon.canApplyAnyImage)
    }

    func nextOccurrence(of event: CelebrationEvent) -> CelebrationOccurrence? {
        event.nextOccurrence(window: preferences.selection(for: event.id).window, from: today)
    }

    /// Enabled celebrations in overlap order.
    var priority: [CelebrationEvent] {
        preferences.order(in: catalog.celebrations).compactMap { catalog.celebration($0) }
    }

    // MARK: - Changes

    /// Choosing a celebration fetches its icons right away, so they're here before its dates.
    func setAutomatic(_ isOn: Bool, for id: CelebrationID) {
        change { $0.setEnabled(isOn, for: id) }
        if isOn { fetchIcons(for: id) }
    }

    func setAppIcon(_ isOn: Bool, for id: CelebrationID) {
        change { $0.selections[id, default: .init()].appIcon = isOn }
        if isOn { fetchIcons(for: id) }
    }

    /// Tries a celebration's icon download again.
    func fetchIcons(for id: CelebrationID) {
        guard let pack = catalog.celebration(id)?.iconPack, preferences.selection(for: id).appIcon else { return }
        assets.fetch(pack)
    }

    func setHome(_ isOn: Bool, for id: CelebrationID) {
        change { $0.selections[id, default: .init()].home = isOn }
    }

    func setWindow(_ window: CelebrationWindow.ID, for id: CelebrationID) {
        change { $0.selections[id, default: .init()].window = window }
    }

    func skip(_ occurrence: CelebrationOccurrence.ID) {
        change {
            $0.skipped.insert(occurrence)
            if $0.chosen == occurrence { $0.chosen = nil }
        }
    }

    func unskip(_ occurrence: CelebrationOccurrence.ID) {
        change { $0.skipped.remove(occurrence) }
    }

    /// Shows `occurrence` over the policy's pick while it lasts; nil goes back to the policy.
    func choose(_ occurrence: CelebrationOccurrence.ID?) {
        change { $0.chosen = occurrence }
    }

    /// Restores the base icon and Home now: skips everything that would show today. Each comes
    /// back next time it occurs, or with `resumeToday`.
    func restoreBase() {
        let showing = [resolution.active?.occurrence].compactMap { $0 } + resolution.runnersUp
        change {
            $0.skipped.formUnion(showing.map(\.id))
            $0.chosen = nil
        }
    }

    /// Undoes skips of what would show today.
    func resumeToday() {
        let skipped = resolution.skipped.map(\.id)
        change { $0.skipped.subtract(skipped) }
    }

    /// Moves a celebration earlier (negative) or later in the overlap order.
    func move(_ id: CelebrationID, by offset: Int) {
        let events = catalog.celebrations
        change { $0.move(id, by: offset, in: events) }
    }

    private func change(_ edit: (inout CelebrationPreferences) -> Void) {
        edit(&preferences)
        save()
        refresh()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.preferencesKey)
    }

    isolated deinit {
        timer?.invalidate()
    }
}
