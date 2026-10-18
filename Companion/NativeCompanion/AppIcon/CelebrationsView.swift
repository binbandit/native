import AppAppearance
import SwiftUI

/// Settings › App Icon › Celebrations: Native's catalogue, every one off until picked, each shown on
/// its dates once on. Turned-on ones come first; the rest are in the order they next come round.
struct CelebrationsView: View {
    @Environment(AppIconController.self) private var icons
    @State private var query = ""

    private var celebrations: CompanionCelebrations { icons.celebrations }

    var body: some View {
        let today = CivilDate.today
        let matching = celebrations.events.filter { query.isEmpty || $0.contribution.matches(query) }
        let byNextDate = matching.sorted { lhs, rhs in
            let left = celebrations.nextOccurrence(of: lhs, from: today)?.display.first
            let right = celebrations.nextOccurrence(of: rhs, from: today)?.display.first
            return switch (left, right) {
            case (let left?, let right?): left < right
            case (.some, nil): true
            case (nil, _): false
            }
        }
        let on = byNextDate.filter { celebrations.selection(for: $0).isEnabled }
        List {
            if on.isEmpty, query.isEmpty {
                Section {
                    Text("Turn one on and the icon changes on its dates, then goes back. Nothing is on until you pick it.")
                        .font(CompanionType.subheadline).foregroundStyle(.dsTextSecondary)
                }
            }
            if !on.isEmpty {
                Section("On") {
                    ForEach(on) { CelebrationRow(event: $0, today: today) }
                }
            }
            Section(on.isEmpty ? "" : "More") {
                ForEach(byNextDate.filter { !celebrations.selection(for: $0).isEnabled }) {
                    CelebrationRow(event: $0, today: today)
                }
            }
        }
        .overlay {
            if matching.isEmpty {
                EmptyStateView(
                    "No celebration called “\(query)”", systemImage: "magnifyingglass",
                    message: "Try another name; local names and spellings count too.")
            }
        }
        .searchable(text: $query, prompt: "Search celebrations")
        .font(CompanionType.body)
        .scrollContentBackground(.hidden)
        .background(.dsBackground)
        .navigationTitle("Celebrations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One celebration: its icon, name and next dates, a switch, and its styles once it's on.
private struct CelebrationRow: View {
    let event: CelebrationEvent
    let today: CivilDate

    @Environment(AppIconController.self) private var icons

    private var celebrations: CompanionCelebrations { icons.celebrations }
    private var selection: CelebrationPreferences.Selection { celebrations.selection(for: event) }
    private var styled: CelebrationEvent { celebrations.preferences.styled(event) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Toggle(
                isOn: Binding(
                    get: { selection.isEnabled },
                    set: { isOn in
                        celebrations.setEnabled(isOn, for: event)
                        icons.applyNow()
                    })
            ) {
                HStack(spacing: DS.Space.lg) {
                    AppIconThumbnail(name: styled.iconSet.map { CompanionCelebrations.iconName(for: $0.id) })
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(event.contribution.title.resolved()).foregroundStyle(.dsTextPrimary)
                        Text(dates).font(CompanionType.caption).foregroundStyle(.dsTextSecondary)
                    }
                }
            }
            .disabled(!event.canBeChosen(on: today) && !selection.isEnabled)
            .accessibilityIdentifier("celebration-\(event.id.rawValue)")
            if selection.isEnabled, event.styles.count > 1 {
                Picker(
                    "Style",
                    selection: Binding(
                        get: { styled.iconSet?.id ?? event.styles[0].id },
                        set: { style in
                            celebrations.setStyle(style, for: event)
                            icons.applyNow()
                        })
                ) {
                    ForEach(event.styles) { style in
                        Text(style.name.resolved()).tag(style.id)
                    }
                }
                .font(CompanionType.subheadline)
            }
        }
    }

    private var dates: String {
        switch event.dateStatus(on: today) {
        case .resolvable:
            guard event.appIcon.isReady else { return "Its icon isn't on iPhone yet." }
            guard let occurrence = celebrations.nextOccurrence(of: event, from: today) else { return "No dates ahead." }
            if occurrence.display.contains(today) {
                return "Now, through \(CelebrationDates.shortText(CivilDayRange(day: occurrence.display.last)))"
            }
            return CelebrationDates.text(occurrence.display)
        case .unsupportedCalendar:
            return "Its dates aren't worked out yet."
        case .coverageEnded(let lastYear):
            return "Its published dates end with \(lastYear)."
        }
    }
}
