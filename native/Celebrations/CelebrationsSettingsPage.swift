import AppAppearance
import SwiftUI

/// Settings ▸ Celebrations, the chooser: what's showing and why, the overlap order, and the whole
/// catalogue all year with each celebration off until the user picks it. Nothing is chosen from the
/// user's locale or region.
struct CelebrationsSettingsPage: View {
    @Environment(CelebrationCenter.self) private var center
    @Environment(PluginRegistry.self) private var plugins
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var undoManager
    @State private var query = ""
    @State private var showsLater = false
    /// The last change to many celebrations at once, so its result and Undo show beside the controls.
    @State private var lastChange: BulkChange?

    private struct BulkChange: Equatable {
        let summary: String
        let before: CelebrationPreferences
    }

    static func rowID(_ id: CelebrationID) -> SettingsRowID {
        SettingsRowID("celebration.\(id.rawValue)")
    }

    private var isPluginEnabled: Bool { plugins.isEnabled(CelebrationsPlugin.id) }

    private var matches: [CelebrationEvent] {
        center.celebrations.filter { $0.contribution.matches(query) }
    }

    /// Ready to use, or already chosen.
    private var available: [CelebrationEvent] {
        matches.filter { $0.canBeChosen(on: center.today) || center.preferences.selection(for: $0.id).isEnabled }
    }

    /// Listed with their calendar (or artwork) still to come.
    private var later: [CelebrationEvent] {
        matches.filter { !$0.canBeChosen(on: center.today) && !center.preferences.selection(for: $0.id).isEnabled }
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Celebrations",
                description: Text(
                    "Native dresses its icon and Home for the celebrations you choose, on their dates, then puts your usual look back. Every one starts off."
                ))
            if !isPluginEnabled {
                turnOn
            }
            if !center.catalog.celebrations.isEmpty {
                CelebrationStatusCard()
                if center.priority.count > 1 {
                    CelebrationPriorityList()
                }
                catalogue
            }
            if !center.catalog.problems.isEmpty {
                problems
            }
        }
        .animation(reduceMotion ? nil : .dsQuick, value: center.priority.map(\.id))
        .animation(reduceMotion ? nil : .dsQuick, value: lastChange)
    }

    private var turnOn: some View {
        SettingsRow(
            "Native's celebrations are off",
            icon: "party.popper",
            description: Text(
                "Turn on the Celebrations extension for Halloween and Día de Muertos. Each one stays off until you choose it here."
            )
        ) {
            Button("Turn On") { plugins.setEnabled(true, for: CelebrationsPlugin.id) }
                .buttonStyle(.ds(.primary, size: .medium))
        }
    }

    private var catalogue: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                "Catalogue",
                note: "Choose any time of year; each shows only on its dates. Nothing is turned on for you.")
            HStack(spacing: DS.Space.sm) {
                CelebrationCountryMenu(counts: CelebrationPreferences.publicHolidayCountries(in: center.celebrations)) {
                    country in
                    let name = CelebrationCountryMenu.name(country)
                    changeUndoably("Turn On \(name) Holidays") {
                        center.turnOnPublicHolidays(of: country)
                    } summary: {
                        "Turned on \($0) of \(name)'s public holidays."
                    }
                }
                bulkControls
                Spacer(minLength: DS.Space.xl)
                CelebrationSearchField(query: $query)
            }
            if let lastChange {
                HStack(spacing: DS.Space.md) {
                    Text(lastChange.summary)
                        .settingsText(.body)
                        .foregroundStyle(.dsTextSecondary)
                    Button("Undo") { undo(lastChange) }
                        .buttonStyle(.ds(.secondary, size: .small))
                        .help("Put your choices back (⌘Z)")
                }
                .transition(.opacity)
            }
            if matches.isEmpty {
                SettingsRow(
                    "Nothing called “\(query.trimmingCharacters(in: .whitespaces))”", icon: "magnifyingglass",
                    description: Text("Search covers names, other names and spellings, and kinds of celebration.")
                ) {
                    Button("Clear Search") { query = "" }
                        .buttonStyle(.ds(.secondary, size: .medium))
                }
            } else {
                if !available.isEmpty {
                    SettingsRowGroup {
                        ForEach(available) { event in
                            CelebrationRow(event: event)
                        }
                    }
                }
                if !later.isEmpty {
                    comingLater
                }
            }
        }
    }

    /// Every celebration on or off in one step, undoable.
    @ViewBuilder private var bulkControls: some View {
        let choosable = center.celebrations.filter { $0.canBeChosen(on: center.today) }
        let enabled = center.celebrations.filter { center.preferences.selection(for: $0.id).isEnabled }
        Button("Turn All On") {
            changeUndoably("Turn All Celebrations On") {
                center.setAllAutomatic(true)
            } summary: {
                "Turned on \($0) \($0 == 1 ? "celebration" : "celebrations"). Icons download a week before each one's dates."
            }
        }
        .buttonStyle(.ds(.ghost, size: .medium))
        .disabled(choosable.allSatisfy { center.preferences.selection(for: $0.id).isEnabled })
        .help("Turn on every celebration. Icons download a week before each one's dates.")
        Button("Turn All Off") {
            changeUndoably("Turn All Celebrations Off") {
                center.setAllAutomatic(false)
            } summary: { _ in
                "Turned every celebration off."
            }
        }
        .buttonStyle(.ds(.ghost, size: .medium))
        .disabled(enabled.isEmpty)
        .help("Turn off every celebration. Undo puts your choices back.")
    }

    /// Makes a change to many celebrations at once, says what changed, and lets Undo (the button or
    /// ⌘Z) put it back. `summary` gets how many celebrations it turned on.
    private func changeUndoably(_ name: String, _ change: () -> Void, summary: (Int) -> String) {
        let before = center.preferences
        change()
        guard before != center.preferences else { return }
        let enabled = { (preferences: CelebrationPreferences) in preferences.selections.values.filter(\.isEnabled).count
        }
        lastChange = BulkChange(summary: summary(max(enabled(center.preferences) - enabled(before), 0)), before: before)
        guard let undoManager else { return }
        Self.registerUndo(on: undoManager, center: center, restoring: before)
        undoManager.setActionName(name)
    }

    /// Puts back the choices from before the change, and drops its ⌘Z entry so it can't be undone twice.
    private func undo(_ change: BulkChange) {
        center.restore(change.before)
        undoManager?.removeAllActions(withTarget: center)
        lastChange = nil
    }

    /// Undo restores `earlier` and registers restoring what it replaced, so Redo works too.
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

    private var comingLater: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.xl) {
                SettingsSubheading(
                    "Coming soon",
                    note:
                        "Their dates are researched; their artwork, and some of their calendars, are still being made.")
                Spacer(minLength: 0)
                if !isSearching {
                    Button(showsLater ? "Hide" : "Show \(later.count)") { showsLater.toggle() }
                        .buttonStyle(.ds(.ghost, size: .medium))
                }
            }
            if showsLater || isSearching {
                SettingsRowGroup {
                    ForEach(later) { event in
                        CelebrationRow(event: event)
                    }
                }
            }
        }
        .padding(.top, available.isEmpty ? 0 : DS.Space.lg)
    }

    private var problems: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading("Couldn't load", note: "Fix the plugin's plugin.json, then Reload in Extensions.")
            SettingsRowGroup {
                ForEach(center.catalog.problems, id: \.self) { problem in
                    SettingsRow(
                        problem.identifier,
                        icon: "exclamationmark.triangle",
                        description: Text(problem.message).foregroundStyle(.dsDanger),
                        detail: Text("\(problem.kind.rawValue) from \(pluginName(problem.pluginID))")
                    ) { EmptyView() }
                }
            }
        }
    }

    private func pluginName(_ id: String?) -> String {
        guard let id else { return "a plugin" }
        return plugins.plugins.first { $0.id == id }?.plugin.manifest.name ?? id
    }
}

/// Filters the catalogue by name, other names and tags, ignoring accents and case.
private struct CelebrationSearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        TextField(
            "Find a celebration", text: $query, prompt: Text("Find a celebration").foregroundStyle(.dsTextTertiary)
        )
        .textFieldStyle(.plain)
        .settingsText(.body)
        .foregroundStyle(.dsTextPrimary)
        .focused($isFocused)
        .padding(.leading, DS.Space.xxxl)
        .padding(.trailing, DS.Space.md)
        .frame(width: CelebrationMetrics.searchWidth, height: DS.Size.controlSM)
        .overlay(alignment: .leading) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SettingsMetrics.searchGlyph))
                .foregroundStyle(.dsTextSecondary)
                .padding(.leading, DS.Space.md + DS.Space.xxs)
                .accessibilityHidden(true)
        }
        .background(.dsBackground, in: shape)
        .overlay { shape.strokeBorder(isFocused ? Color.dsAccent : Color.dsBorder, lineWidth: 1) }
        .onKeyPress(.escape) {
            guard !query.isEmpty else { return .ignored }
            query = ""
            return .handled
        }
        .accessibilityLabel("Find a celebration")
    }
}

extension CelebrationMetrics {
    static let searchWidth: CGFloat = 220
}
