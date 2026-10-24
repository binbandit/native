import AppAppearance
import NativeCommands
import SwiftUI

/// What's showing today and why, what comes next, and the ways out: show the other celebration
/// instead, skip this one, or put the usual look back now.
struct CelebrationStatusCard: View {
    @Environment(CelebrationCenter.self) private var center
    @Environment(\.releaseChannel) private var channel

    private var resolution: CelebrationResolution { center.resolution }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                if let event = center.activeEvent {
                    CelebrationPreview(event: event, size: CelebrationMetrics.statusPreview)
                } else {
                    CelebrationHomePreview(look: nil, channel: channel)
                        .padding(CelebrationMetrics.statusPreview * 0.2)
                        .frame(width: CelebrationMetrics.statusPreview, height: CelebrationMetrics.statusPreview)
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(headline)
                        .settingsText(.bodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    if let reason {
                        Text(reason)
                            .settingsText(.body)
                            .foregroundStyle(.dsTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions
                        .padding(.top, DS.Space.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            let upcoming = center.schedule()
            if upcoming.contains(where: { $0.occurrence != nil }) {
                SeparatorLine()
                CelebrationTimeline(segments: upcoming)
            }
        }
        .padding(DS.Space.xl)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                .strokeBorder(.dsSeparator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func title(_ id: CelebrationID) -> String {
        center.catalog.celebration(id)?.contribution.title.resolved() ?? id.rawValue
    }

    private var headline: String {
        guard let active = resolution.active else {
            if let skipped = resolution.skipped.first {
                return "\(title(skipped.eventID)) is skipped this year"
            }
            if let waiting = center.waitingForIcons {
                return "\(waiting.event.contribution.title.resolved()) is waiting for its icons"
            }
            return "Your usual look today"
        }
        let surfaces = [active.appliesToAppIcon ? "app icon" : nil, active.appliesToHome ? "Home" : nil]
            .compactMap { $0 }.joined(separator: " and ")
        return
            "\(title(active.eventID)) is on your \(surfaces) until \(CelebrationDates.shortText(CivilDayRange(day: active.occurrence.display.last)))"
    }

    private var reason: String? {
        guard let active = resolution.active else {
            if let waiting = center.waitingForIcons, resolution.skipped.isEmpty {
                return switch waiting.state {
                case .failed(let reason), .unavailable(let reason): reason + " Your usual look stays meanwhile."
                case .downloading: "Downloading them now; it shows as soon as they're here."
                case .notDownloaded, .ready: "They download in a moment; it shows as soon as they're here."
                }
            }
            return resolution.skipped.isEmpty ? nil : "Your usual icon and Home are back until it next occurs."
        }
        let why: String? =
            switch active.reason {
            case .only: nil
            case .chosen(let other): "You chose it over \(title(other)) for now."
            case .coreDates(let other):
                "These are its own dates, so it shows instead of \(title(other))'s longer window."
            case .priority(let other): "It comes before \(title(other)) in your order below."
            }
        let parts = [why, iconNote(active)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Why the icon isn't changing with Home, when that's not the user's own choice.
    private func iconNote(_ active: CelebrationResolution.Active) -> String? {
        guard !active.appliesToAppIcon, let event = center.activeEvent,
            center.preferences.selection(for: event.id).appIcon
        else { return nil }
        if !PlatformAppIcon.canApplyAnyImage { return "The app icon can't change on this device." }
        switch event.appIcon {
        case .forthcoming: return "Its app icon is still being drawn, so the icon stays as it is."
        case .downloadable(.unavailable(let reason)): return reason
        case .downloadable(.failed(let reason)): return reason
        case .downloadable: return "Its icon is downloading; the icon changes when it's here."
        default: return nil
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: DS.Space.md) {
            if let active = resolution.active {
                if let other = resolution.runnersUp.first {
                    Button("Show \(title(other.eventID)) Instead") { center.choose(other.id) }
                        .buttonStyle(.ds(.secondary, size: .medium))
                }
                Button("Restore Usual Look") { center.restoreBase() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .help(
                        CommandRegistry.shared.help(
                            "Skip what's showing today. It comes back next time it occurs.", for: .celebrationRestore))
                if case .chosen = active.reason {
                    Button("Use My Order") { center.choose(nil) }
                        .buttonStyle(.ds(.ghost, size: .medium))
                }
            } else if let waiting = center.waitingForIcons, case .failed = waiting.state {
                Button("Retry") { center.fetchIcons(for: waiting.event.id) }
                    .buttonStyle(.ds(.secondary, size: .medium))
            } else if !resolution.skipped.isEmpty {
                Button("Bring Back") { center.resumeToday() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .help(CommandRegistry.shared.help("Show the skipped celebration again.", for: .celebrationRestore))
            }
        }
    }
}

/// The next weeks at a glance: which celebration shows when, and when the usual look returns.
private struct CelebrationTimeline: View {
    let segments: [CelebrationScheduleSegment]

    @Environment(CelebrationCenter.self) private var center

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Coming up")
                .settingsText(.caption)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                HStack(spacing: DS.Space.md) {
                    Circle()
                        .fill(segment.occurrence == nil ? Color.dsTextQuaternary : Color.dsAccent)
                        .frame(width: DS.Space.sm, height: DS.Space.sm)
                    Text(days(segment, isLast: index == segments.count - 1))
                        .settingsText(.body)
                        .foregroundStyle(.dsTextSecondary)
                        .frame(minWidth: CelebrationMetrics.timelineDates, alignment: .leading)
                    Text(name(segment))
                        .settingsText(.body)
                        .foregroundStyle(segment.occurrence == nil ? Color.dsTextTertiary : Color.dsTextPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func days(_ segment: CelebrationScheduleSegment, isLast: Bool) -> String {
        let start =
            segment.days.first == center.today
            ? "Today" : CelebrationDates.shortText(CivilDayRange(day: segment.days.first))
        if isLast, segment.occurrence == nil { return "From \(start)" }
        if segment.days.first == segment.days.last { return start }
        return "\(start) – \(CelebrationDates.shortText(CivilDayRange(day: segment.days.last)))"
    }

    private func name(_ segment: CelebrationScheduleSegment) -> String {
        guard let occurrence = segment.occurrence else { return "Your usual look" }
        return center.catalog.celebration(occurrence.eventID)?.contribution.title.resolved()
            ?? occurrence.eventID.rawValue
    }
}

extension CelebrationMetrics {
    static let timelineDates: CGFloat = 150
}

#if DEBUG
#Preview("Celebration status - Downloads disabled, Home available") {
    let center = CelebrationPreviewFixtures.downloadsDisabled()
    DSPreviewPair {
        if let center {
            CelebrationStatusCard()
                .environment(center)
                .settingsPreviewPage()
        }
    }
}
#endif
