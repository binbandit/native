import AppAppearance
import NativePolicy
import SwiftUI

/// The catalogue stays compact: today's look, a year, genuine collisions, then months.
struct CelebrationsSettingsPage: View {
    var organizationName: String?

    @Environment(CelebrationCenter.self) private var center
    @Environment(PluginRegistry.self) private var plugins
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.settingsScrollTo) private var scrollTo
    @Environment(\.settingsFlash) private var settingsFlash
    @Environment(\.undoManager) private var undoManager
    @State private var query = ""
    @State private var showsLater = false
    @State private var detail: CelebrationID?
    @State private var reveal: SettingsReveal?
    @State private var lastChange: CelebrationBulkChange?
    @State private var flashed: Set<CelebrationID> = []

    static func rowID(_ id: CelebrationID) -> SettingsRowID { SettingsRowID("celebration.\(id.rawValue)") }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Group {
            if let detail, let event = center.celebrations.first(where: { $0.id == detail }) {
                CelebrationDetailPage(event: event) { settings.goBack() }
            } else {
                list
            }
        }
        .environment(\.settingsFlash, reveal ?? settingsFlash)
        .onChange(of: settingsFlash) { reveal = nil }
        .onChange(of: center.preferences) { _, preferences in
            if lastChange?.after != preferences { lastChange = nil }
        }
        .onDisappear {
            settings.showDetail(nil); lastChange = nil
        }
    }

    private static func monthID(_ month: CivilDate) -> SettingsRowID {
        SettingsRowID("celebration-month.\(month.year)-\(month.month)")
    }

    private func open(_ id: CelebrationID) {
        settings.showDetail(id.rawValue) { detail = nil }
        lastChange = nil
        detail = id
    }

    private var list: some View {
        SettingsPage {
            SettingsHeader(
                "Celebrations",
                description: Text(
                    "Native dresses its icon and Home on the days you choose, then puts your look back."))
            if !plugins.isEnabled(CelebrationsPlugin.id) { turnOn }
            if hasUnavailableIcons {
                CelebrationOfflineNotice(
                    organizationName: organizationName ?? PolicyCenter.shared.policy.organizationName)
            }
            if !center.catalog.celebrations.isEmpty {
                CelebrationStatusCard(
                    reveal: { id in
                        query = ""
                        Task { @MainActor in
                            await Task.yield()
                            scrollTo?(Self.rowID(id), .center)
                            reveal = SettingsReveal(rowID: Self.rowID(id))
                        }
                    },
                    revealMonth: { month in
                        query = ""
                        Task { @MainActor in
                            await Task.yield()
                            scrollTo?(Self.monthID(month), .top)
                        }
                    },
                    chooseRegion: {
                        if let region = Locale.current.region?.identifier { chooseCountry(region) }
                    })
                CelebrationOverlaps(overlaps: center.overlaps(within: 365))
                catalogue
            }
            if !center.catalog.problems.isEmpty { problems }
        }
    }

    private var turnOn: some View {
        SettingsRow(
            "Native's celebrations are off", icon: "party.popper",
            description: Text("Each celebration stays off until you choose it here.")
        ) {
            Button("Turn On") { plugins.setEnabled(true, for: CelebrationsPlugin.id) }.buttonStyle(.settings)
        }
    }

    private var hasUnavailableIcons: Bool {
        center.celebrations.contains { if case .downloadable(.unavailable) = $0.appIcon { true } else { false } }
    }

    private var catalogue: some View {
        let listing = CelebrationListing(
            events: center.celebrations, preferences: center.preferences, today: center.today, query: query)
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack {
                SettingsSubheading("All celebrations")
                Spacer()
                Text(
                    isSearching
                        ? "\(listing.matchCount) \(listing.matchCount == 1 ? "match" : "matches")"
                        : "\(center.priority.count) of \(center.celebrations.count) on"
                )
                .settingsText(.caption).foregroundStyle(.dsTextTertiary)
            }
            HStack(spacing: DS.Space.md) {
                SearchField("Find a celebration", text: $query, font: SettingsTextStyle.body.font)
                bulkMenu
            }
            if let lastChange {
                CelebrationBulkConfirmation(summary: lastChange.summary) { undo(lastChange) }
            }
            if listing.matchCount == 0 {
                SettingsRow(
                    "Nothing called “\(query.trimmingCharacters(in: .whitespaces))”", icon: "magnifyingglass",
                    description: Text("Search covers names, other names and spellings, and kinds of celebration.")
                ) {
                    Button("Clear Search") { query = "" }.buttonStyle(.settings)
                }
            }
            ForEach(listing.months) { section in
                let month = section.id
                let events = section.events
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    HStack {
                        Text(CelebrationDates.month(month, includeYear: month.year != center.today.year))
                            .settingsText(.bodyMedium).foregroundStyle(.dsTextPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(events.filter { center.preferences.selection(for: $0.id).isEnabled }.count) on")
                            .settingsText(.caption).foregroundStyle(.dsTextTertiary)
                    }
                    .id(Self.monthID(month))
                    // Compact rows own their 44pt height; the standard group supplies separators.
                    SettingsRowGroup {
                        VStack(spacing: 0) {
                            ForEach(events) { event in
                                if event.id != events.first?.id { SeparatorLine().padding(.leading, DS.Space.xl) }
                                CelebrationRow(event: event, query: query, flash: flashed.contains(event.id)) {
                                    open(event.id)
                                }
                            }
                        }
                    }
                }
            }
            if !listing.pending.isEmpty { comingLater(listing.pending) }
        }
    }

    private var bulkMenu: some View {
        Menu {
            CelebrationCountryMenu(
                counts: CelebrationPreferences.publicHolidayCountries(in: center.celebrations), onPick: chooseCountry)
            Divider()
            Button("Turn All On") { changeUndoably("Turn All Celebrations On") { center.setAllAutomatic(true) } }
                .disabled(
                    center.celebrations.filter { $0.canBeChosen(on: center.today) }.allSatisfy {
                        center.preferences.selection(for: $0.id).isEnabled
                    })
            Button("Turn All Off") { changeUndoably("Turn All Celebrations Off") { center.setAllAutomatic(false) } }
                .disabled(center.priority.isEmpty)
        } label: {
            Image(systemName: "ellipsis").frame(width: CelebrationMetrics.menuSize, height: CelebrationMetrics.menuSize)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .buttonStyle(.settings).dsHitTarget(CelebrationMetrics.menuSize).accessibilityLabel("Celebration choices")
    }

    private func chooseCountry(_ country: String) {
        let already = center.celebrations.filter {
            $0.contribution.publicHolidays.contains(country) && center.preferences.selection(for: $0.id).isEnabled
        }.map { $0.contribution.title.resolved() }
        changeUndoably("Turn On \(CelebrationCountryMenu.name(country)) Holidays", already: already, nameEach: true) {
            center.turnOnPublicHolidays(of: country)
        }
    }

    private func changeUndoably(_ name: String, already: [String] = [], nameEach: Bool = false, _ change: () -> Void) {
        let before = center.preferences
        change()
        guard before != center.preferences else { return }
        let enabled = center.celebrations.filter {
            center.preferences.selection(for: $0.id).isEnabled && !before.selection(for: $0.id).isEnabled
        }
        flashed = Set(enabled.map(\.id))
        let summary =
            enabled.isEmpty
            ? "Turned every celebration off."
            : nameEach
                ? "Turned on \(enabled.map { $0.contribution.title.resolved() }.formatted(.list(type: .and)))."
                : "Turned on \(enabled.count) celebrations."
        let suffix =
            already.isEmpty
            ? "" : " \(already.formatted(.list(type: .and))) \(already.count == 1 ? "was" : "were") already on."
        lastChange = CelebrationBulkChange(summary: summary + suffix, before: before, after: center.preferences)
        if let undoManager {
            Self.registerUndo(on: undoManager, center: center, restoring: before)
            undoManager.setActionName(name)
        }
    }

    private func undo(_ change: CelebrationBulkChange) {
        if let undoManager, undoManager.canUndo { undoManager.undo() } else { center.restore(change.before) }
        lastChange = nil
        flashed = []
    }

    private static func registerUndo(
        on undoManager: UndoManager, center: CelebrationCenter, restoring earlier: CelebrationPreferences
    ) {
        let replaced = center.preferences
        undoManager.registerUndo(withTarget: center) { center in
            MainActor.assumeIsolated {
                center.restore(earlier)
                registerUndo(on: undoManager, center: center, restoring: replaced)
            }
        }
    }

    private func comingLater(_ later: [CelebrationEvent]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Button {
                showsLater.toggle()
            } label: {
                HStack(spacing: DS.Space.lg) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("\(later.count) more on the way").settingsText(.body)
                        Text("Their artwork or dates are still being made.").settingsText(.caption).foregroundStyle(
                            .dsTextSecondary)
                    }
                    Spacer()
                    Image(systemName: showsLater ? "chevron.down" : "chevron.right")
                        .font(.system(size: CelebrationMetrics.chevron)).foregroundStyle(.dsTextTertiary)
                }
            }.buttonStyle(.plain)
            if showsLater || isSearching {
                VStack(spacing: 0) {
                    ForEach(later) { event in
                        CelebrationRow(event: event, query: query) { open(event.id) }
                    }
                }
            }
        }
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading("Couldn't load", note: "Fix the plugin's plugin.json, then Reload in Extensions.")
            ForEach(center.catalog.problems, id: \.self) { problem in
                NoticeBanner(tone: .danger, title: "\(problem.identifier) couldn't load", detail: problem.message)
            }
        }
    }
}

private struct CelebrationBulkChange {
    let summary: String
    let before: CelebrationPreferences
    let after: CelebrationPreferences
}
