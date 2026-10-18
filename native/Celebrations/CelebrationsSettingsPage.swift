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
            HStack(spacing: DS.Space.xl) {
                SettingsSubheading(
                    "Catalogue",
                    note: "Choose any time of year; each shows only on its dates. Packs never turn one on for you.")
                Spacer(minLength: 0)
                bulkControls
                CelebrationSearchField(query: $query)
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
        Button("Turn All On") { changeAll(to: true) }
            .buttonStyle(.ds(.ghost, size: .medium))
            .disabled(choosable.allSatisfy { center.preferences.selection(for: $0.id).isEnabled })
            .help("Turn on every celebration. Icons download a week before each one's dates.")
        Button("Turn All Off") { changeAll(to: false) }
            .buttonStyle(.ds(.ghost, size: .medium))
            .disabled(enabled.isEmpty)
            .help("Turn off every celebration. Undo puts your choices back.")
    }

    private func changeAll(to isOn: Bool) {
        let before = center.preferences
        center.setAllAutomatic(isOn)
        guard let undoManager, before != center.preferences else { return }
        Self.registerUndo(on: undoManager, center: center, restoring: before)
        undoManager.setActionName(isOn ? "Turn All Celebrations On" : "Turn All Celebrations Off")
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
