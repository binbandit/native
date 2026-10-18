import AppAppearance
import SwiftUI

/// One celebration in the catalogue: its preview, names, next dates and whether it's ready, with
/// "Celebrate automatically" on the right. Switched on, it shows its own choices underneath: which
/// surfaces change, how long it shows, and skipping this year's.
struct CelebrationRow: View {
    let event: CelebrationEvent

    @Environment(CelebrationCenter.self) private var center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var contribution: CelebrationContribution { event.contribution }
    private var selection: CelebrationPreferences.Selection { center.preferences.selection(for: event.id) }
    private var occurrence: CelebrationOccurrence? { center.nextOccurrence(of: event) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                CelebrationPreview(event: event)
                SettingsRow(
                    id: CelebrationsSettingsPage.rowID(event.id),
                    title: Text(contribution.title.resolved()),
                    description: Text(description),
                    detail: Text(details.joined(separator: "\n"))
                ) {
                    if event.display.treatment == .quiet { SettingsBadge("Quiet") }
                    if let status { SettingsBadge(status) }
                    if contribution.calendar.isProvisional { SettingsBadge("Provisional") }
                } control: {
                    SettingsSwitch(
                        "Celebrate \(contribution.title.resolved()) automatically",
                        isOn: Binding(get: { selection.isEnabled }, set: { center.setAutomatic($0, for: event.id) })
                    )
                    .disabled(!event.canBeChosen(on: center.today) && !selection.isEnabled)
                    .help(status ?? "Show it on its dates")
                }
            }
            if selection.isEnabled {
                CelebrationOptions(event: event, occurrence: occurrence)
                    .padding(.leading, CelebrationMetrics.optionsInset)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .dsQuick, value: selection.isEnabled)
    }

    private var description: String {
        var parts = [contribution.summary?.resolved()].compactMap { $0 }
        if !contribution.aliases.isEmpty {
            parts.append("Also " + contribution.aliases.prefix(3).joined(separator: ", ") + ".")
        }
        return parts.joined(separator: " ")
    }

    private var details: [String] {
        var lines: [String] = []
        switch event.dateStatus(on: center.today) {
        case .resolvable:
            if let occurrence {
                let prefix = occurrence.display.contains(center.today) ? "Showing" : "Next"
                var line = "\(prefix): \(CelebrationDates.text(occurrence.display))"
                if occurrence.core != occurrence.display {
                    line += " · \(contribution.title.resolved()) itself: \(CelebrationDates.shortText(occurrence.core))"
                }
                lines.append(line)
            }
        case .unsupportedCalendar:
            lines.append("Native can't work out its dates yet, so it never changes anything.")
        case .coverageEnded(let year):
            lines.append(
                "Its published dates end in \(year.formatted(.number.grouping(.never))); the usual look stays.")
        }
        if let tradition = contribution.calendar.tradition {
            lines.append(tradition)
        }
        if let authority = contribution.provenance.authority {
            lines.append("Dates from \(authority)")
        }
        // The source's first point, such as an evening start; the rest is for checking the dates.
        if let note = contribution.provenance.note?.split(separator: ". ").first {
            lines.append(note.hasSuffix(".") ? String(note) : note + ".")
        }
        return lines
    }

    /// Why it can't be chosen yet, if it can't.
    private var status: String? {
        if event.dateStatus(on: center.today) != .resolvable { return "Coming soon" }
        if event.canBeChosen(on: center.today) { return nil }
        switch (event.appIcon, event.home) {
        case (.unavailable, _), (_, .unavailable): return "Artwork missing"
        default: return "Artwork forthcoming"
        }
    }
}

/// A switched-on celebration's own choices.
private struct CelebrationOptions: View {
    let event: CelebrationEvent
    let occurrence: CelebrationOccurrence?

    @Environment(CelebrationCenter.self) private var center
    @Environment(\.releaseChannel) private var channel
    @Environment(\.colorScheme) private var colorScheme

    private var selection: CelebrationPreferences.Selection { center.preferences.selection(for: event.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            surface(
                "App icon", isIcon: true, preview: AnyView(iconPreview), status: event.appIcon,
                isOn: Binding(get: { selection.appIcon }, set: { center.setAppIcon($0, for: event.id) }))
            surface(
                "Home", isIcon: false, preview: AnyView(CelebrationHomePreview(look: event.homeLook, channel: channel)),
                status: event.home,
                isOn: Binding(get: { selection.home }, set: { center.setHome($0, for: event.id) }))
            if event.styles.count > 1, let current = event.iconSet {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack(spacing: DS.Space.xl) {
                        Text("Style")
                            .settingsText(.body)
                            .foregroundStyle(.dsTextSecondary)
                        Spacer(minLength: 0)
                        SettingsSelect(
                            label: "\(event.contribution.title.resolved()) style",
                            selection: Binding(get: { current.id }, set: { center.setStyle($0, for: event.id) }),
                            options: event.styles.map { .init(value: $0.id, title: $0.name.resolved()) },
                            width: CelebrationMetrics.windowSelectWidth)
                    }
                    if let caption = current.contribution.caption {
                        Text(caption.resolved())
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                    }
                }
            }
            if !event.display.windows.isEmpty {
                HStack(spacing: DS.Space.xl) {
                    Text("Show for")
                        .settingsText(.body)
                        .foregroundStyle(.dsTextSecondary)
                    Spacer(minLength: 0)
                    SettingsSelect(
                        label: "How long \(event.contribution.title.resolved()) shows",
                        selection: Binding(
                            get: { event.display.window(selection.window).id },
                            set: { center.setWindow($0, for: event.id) }),
                        options: event.display.choices.map { .init(value: $0.id, title: windowTitle($0)) },
                        width: CelebrationMetrics.windowSelectWidth)
                }
            }
            if let occurrence {
                skipRow(occurrence)
            }
        }
    }

    @ViewBuilder private var iconPreview: some View {
        if let icon = event.icon(for: center.variant, isDark: colorScheme == .dark) {
            PlatformAppIcon.preview(icon).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed").foregroundStyle(.dsTextTertiary)
        }
    }

    private func surface(
        _ title: String, isIcon: Bool, preview: AnyView, status: AppearanceSurfaceStatus, isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: DS.Space.lg) {
            preview
                .frame(width: CelebrationMetrics.surfacePreview, height: CelebrationMetrics.surfacePreview)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextPrimary)
                if let note = note(for: status, isIcon: isIcon) {
                    Text(note)
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            Spacer(minLength: 0)
            if case .downloadable(.failed) = status {
                Button("Retry") { center.fetchIcons(for: event.id) }
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
            SettingsSwitch("\(event.contribution.title.resolved()) \(title.lowercased())", isOn: isOn)
                .disabled(!status.isReady && !status.isDownloadable)
        }
    }

    private func note(for status: AppearanceSurfaceStatus, isIcon: Bool) -> String? {
        switch status {
        case .ready:
            isIcon && !PlatformAppIcon.canApplyAnyImage
                ? "Mac only" : isIcon ? "Celebration icons don't have Clear or Tinted looks." : nil
        case .forthcoming: "Artwork forthcoming. Until it's ready, this stays as it is."
        case .notOffered: "This celebration doesn't change it."
        case .unavailable(let reason): reason
        case .downloadable(.notDownloaded), .downloadable(.ready):
            "Downloads now, or a week before its dates. Until then, your icon stays as it is."
        case .downloadable(.downloading): "Downloading…"
        case .downloadable(.failed(let reason)): reason
        }
    }

    private func windowTitle(_ window: CelebrationWindow) -> String {
        let days = occurrence.map {
            CelebrationDates.shortText($0.core.expanded(before: window.daysBefore, after: window.daysAfter))
        }
        let title = window.isCore ? "Core dates" : window.title.resolved()
        return [title, days].compactMap { $0 }.joined(separator: " · ")
    }

    private func skipRow(_ occurrence: CelebrationOccurrence) -> some View {
        let isSkipped = center.preferences.skipped.contains(occurrence.id)
        let year = occurrence.core.first.year.formatted(.number.grouping(.never))
        return HStack(spacing: DS.Space.xl) {
            Text(
                isSkipped
                    ? "Skipping \(year). It comes back next time."
                    : "This year's \(event.contribution.title.resolved())"
            )
            .settingsText(.body)
            .foregroundStyle(.dsTextSecondary)
            Spacer(minLength: 0)
            Button(isSkipped ? "Bring Back" : "Skip \(year)") {
                isSkipped ? center.unskip(occurrence.id) : center.skip(occurrence.id)
            }
            .buttonStyle(.ds(.secondary, size: .medium))
            .help(isSkipped ? "Show it on its dates again" : "Leave this year's out; next year's still shows")
        }
    }
}

extension CelebrationMetrics {
    static let windowSelectWidth: CGFloat = 260
}
