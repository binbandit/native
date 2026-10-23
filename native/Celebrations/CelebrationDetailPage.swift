import AppAppearance
import SwiftUI

/// A celebration's facts and choices stay here, so choosing it never expands the catalogue.
struct CelebrationDetailPage: View {
    let event: CelebrationEvent
    var back: () -> Void = {}

    @Environment(CelebrationCenter.self) private var center
    @Environment(\.releaseChannel) private var channel

    private var selection: CelebrationPreferences.Selection { center.preferences.selection(for: event.id) }
    private var occurrence: CelebrationOccurrence? { center.nextOccurrence(of: event) }
    private var title: String { event.contribution.title.resolved() }
    private var showing: Bool { center.resolution.active?.eventID == event.id }
    private var iconUnavailable: Bool {
        if case .downloadable(.unavailable) = event.appIcon { return true }
        return !event.appIcon.isReady && !event.appIcon.isDownloadable
    }

    var body: some View {
        SettingsPage {
            Button("Celebrations", systemImage: "chevron.left", action: back)
                .buttonStyle(.settings).accessibilityLabel("Back to Celebrations")
            HStack(spacing: DS.Space.xl) {
                CelebrationPreview(event: event, size: CelebrationMetrics.detailPreview)
                SettingsHeader(title: title, description: event.contribution.summary.map { Text($0.resolved()) }) {
                    SettingsSwitch(
                        "Celebrate \(title) automatically",
                        isOn: Binding(
                            get: { selection.isEnabled }, set: { center.setAutomatic($0, for: event.id) })
                    )
                    .disabled(!event.canBeChosen(on: center.today))
                }
            }
            facts
            if !event.display.windows.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    SettingsSubheading("Shows for")
                    SettingsRowGroup {
                        SettingsRow("Season") {
                            SettingsSelect(
                                label: "How long \(title) shows",
                                selection: Binding(
                                    get: { event.display.window(selection.window).id },
                                    set: { center.setWindow($0, for: event.id) }),
                                options: event.display.choices.map { .init(value: $0.id, title: windowTitle($0)) },
                                width: CelebrationMetrics.windowSelectWidth)
                        }
                    }
                    Text(
                        "A celebration on its own dates wins over another's longer season. When it ends, the longer season comes back."
                    )
                    .settingsText(.caption).foregroundStyle(.dsTextSecondary)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                SettingsSubheading("What changes")
                SettingsRowGroup {
                    HStack(spacing: DS.Space.lg) {
                        CelebrationPreview(event: event)
                        SettingsRow("App icon", description: Text(iconNote)) {
                            if case .downloadable(.failed) = event.appIcon {
                                Button("Retry") { center.fetchIcons(for: event.id) }.buttonStyle(.settings)
                            }
                            SettingsSwitch(
                                "\(title) app icon",
                                isOn: Binding(
                                    get: { !iconUnavailable && selection.appIcon },
                                    set: { center.setAppIcon($0, for: event.id) })
                            )
                            .disabled(iconUnavailable || !PlatformAppIcon.canApplyAnyImage)
                        }
                    }
                    HStack(spacing: DS.Space.lg) {
                        CelebrationHomePreview(look: event.homeLook, channel: channel)
                            .frame(width: CelebrationMetrics.surfacePreview, height: CelebrationMetrics.surfacePreview)
                        SettingsRow("Home", description: event.home.isReady ? nil : Text("Artwork coming")) {
                            SettingsSwitch(
                                "\(title) Home",
                                isOn: Binding(
                                    get: { event.home.isReady && selection.home },
                                    set: { center.setHome($0, for: event.id) })
                            )
                            .disabled(!event.home.isReady)
                        }
                    }
                    if event.styles.count > 1, let current = event.iconSet {
                        SettingsRow("Style", description: current.contribution.caption.map { Text($0.resolved()) }) {
                            SettingsSelect(
                                label: "\(title) style",
                                selection: Binding(get: { current.id }, set: { center.setStyle($0, for: event.id) }),
                                options: event.styles.map { .init(value: $0.id, title: $0.name.resolved()) })
                        }
                    }
                }
            }
            if let occurrence { thisYear(occurrence) }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if !event.contribution.aliases.isEmpty {
                    Text("Also called \(event.contribution.aliases.formatted(.list(type: .and))).")
                }
                if let authority = event.contribution.provenance.authority { Text("Dates from \(authority)") }
                if let note = event.contribution.provenance.note { Text(note) }
            }
            .settingsText(.caption).foregroundStyle(.dsTextTertiary)
        }
    }

    private var facts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.xl) { factLabels }
            VStack(alignment: .leading, spacing: DS.Space.md) { factLabels }
        }
        .settingsText(.caption).foregroundStyle(.dsTextSecondary)
    }

    @ViewBuilder private var factLabels: some View {
        if let occurrence {
            fact(
                "clock",
                showing
                    ? "Showing until \(CelebrationDates.shortText(CivilDayRange(day: occurrence.display.last)))"
                    : "Next: \(CelebrationDates.text(occurrence.display))")
            if occurrence.core != occurrence.display {
                fact("star", "\(CelebrationDates.shortText(occurrence.core)) is \(title) itself")
            }
        } else {
            fact("clock", "Dates coming")
        }
        fact("calendar", event.contribution.calendar.tradition ?? "Gregorian calendar")
    }

    private func fact(_ glyph: String, _ text: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: glyph).font(.system(size: CelebrationMetrics.factGlyph)).foregroundStyle(.dsTextTertiary)
            Text(text)
        }
    }

    private var iconNote: String {
        switch event.appIcon {
        case .downloadable(.unavailable): "Needs a download"
        case .downloadable(.failed(let reason)): reason
        case .downloadable(.downloading): "Downloading…"
        case .forthcoming, .unavailable, .notOffered: "Artwork coming"
        default: PlatformAppIcon.canApplyAnyImage ? "No Clear or Tinted look while it shows." : "Mac only"
        }
    }

    private func windowTitle(_ window: CelebrationWindow) -> String {
        let days = occurrence.map {
            CelebrationDates.shortText($0.core.expanded(before: window.daysBefore, after: window.daysAfter))
        }
        return [window.isCore ? "\(title) itself" : window.title.resolved(), days].compactMap { $0 }.joined(
            separator: " · ")
    }

    private func thisYear(_ occurrence: CelebrationOccurrence) -> some View {
        let skipped = center.preferences.skipped.contains(occurrence.id)
        let year = occurrence.core.first.year.formatted(.number.grouping(.never))
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading("This year")
            SettingsRowGroup {
                SettingsRow(
                    "\(title) \(year)",
                    description: Text(
                        skipped
                            ? "Skipped this year"
                            : showing
                                ? "Showing now, until \(CelebrationDates.shortText(CivilDayRange(day: occurrence.display.last)))"
                                : CelebrationDates.text(occurrence.display))
                ) {
                    Button(skipped ? "Bring Back" : "Skip \(year)") {
                        skipped ? center.unskip(occurrence.id) : center.skip(occurrence.id)
                    }.buttonStyle(.settings)
                }
            }
            Text(
                "Skipping puts your usual look back now. Next \(CelebrationDates.month(occurrence.display.first)) it shows again."
            )
            .settingsText(.caption).foregroundStyle(.dsTextSecondary)
        }
    }
}

#if DEBUG
#Preview("Celebrations - Halloween") {
    DSPreviewPair { CelebrationPreviewGallery(.detail).settingsPreviewPage() }.environment(SettingsPresentation())
}
#endif
