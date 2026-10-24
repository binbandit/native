import AppAppearance
import SwiftUI

/// Today has one explanation and one way back; the year stays in the same group.
struct CelebrationStatusCard: View {
    var reveal: (CelebrationID) -> Void = { _ in }
    var revealMonth: (CivilDate) -> Void = { _ in }
    var chooseCountry: (String) -> Void = { _ in }

    @Environment(CelebrationCenter.self) private var center
    @Environment(\.releaseChannel) private var channel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.xl) {
                if let event = center.activeEvent ?? center.waitingForIcons?.event {
                    CelebrationPreview(event: event, size: CelebrationMetrics.statusPreview)
                } else {
                    CelebrationHomePreview(look: nil, channel: channel)
                        .padding(DS.Space.md)
                        .frame(width: CelebrationMetrics.statusPreview, height: CelebrationMetrics.statusPreview)
                        .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(headline).settingsText(.bodyMedium).foregroundStyle(.dsTextPrimary)
                    Text(reason).settingsText(.body).foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                action.buttonStyle(.settings)
            }
            .padding(.horizontal, DS.Space.xl)
            SeparatorLine()
            CelebrationYearStrip(reveal: reveal, revealMonth: revealMonth, chooseCountry: chooseCountry)
        }
        .padding(.vertical, DS.Space.xl)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.panel).strokeBorder(
                .dsSeparator, lineWidth: CelebrationMetrics.hairline)
        }
        .accessibilityElement(children: .contain)
    }

    private func title(_ id: CelebrationID) -> String {
        center.catalog.celebration(id)?.contribution.title.resolved() ?? id.rawValue
    }

    private var headline: String {
        if let active = center.resolution.active {
            let surfaces =
                active.appliesToAppIcon ? (active.appliesToHome ? "your icon and Home" : "your icon") : "Home"
            return "\(title(active.eventID)) is on \(surfaces)"
        }
        if let skipped = center.resolution.skipped.first { return "\(title(skipped.eventID)) is skipped this year" }
        if let waiting = center.waitingForIcons { return "\(title(waiting.event.id)) is waiting for its icons" }
        return "Your usual look"
    }

    private var reason: String {
        if let active = center.resolution.active {
            let until = "Until \(CelebrationDates.shortText(CivilDayRange(day: active.occurrence.display.last)))."
            if let event = center.activeEvent, !active.appliesToAppIcon,
                center.preferences.selection(for: event.id).appIcon
            {
                if case .downloadable(.unavailable(let reason)) = event.appIcon {
                    return "\(until) \(reason)"
                }
                if case .downloadable(.failed(let reason)) = event.appIcon { return "\(until) \(reason)" }
                if case .downloadable = event.appIcon { return "\(until) Its icon is downloading." }
            }
            if active.occurrence.core != active.occurrence.display {
                return
                    "\(until) \(CelebrationDates.shortText(active.occurrence.core)) is \(title(active.eventID)) itself."
            }
            return until
        }
        if let skipped = center.resolution.skipped.first {
            return "Your usual icon and Home are back until next \(CelebrationDates.month(skipped.display.first))."
        }
        if let waiting = center.waitingForIcons {
            return switch waiting.state {
            case .failed(let reason), .unavailable(let reason): reason + " Your usual look stays meanwhile."
            case .downloading: "Downloading them now; it shows as soon as they're here."
            case .notDownloaded, .ready: "They download in a moment; it shows as soon as they're here."
            }
        }
        return center.priority.isEmpty
            ? "Nothing chosen yet. Each celebration shows only on its own dates."
            : "Each celebration shows only on its own dates."
    }

    @ViewBuilder private var action: some View {
        if center.resolution.active != nil {
            Button("Restore Usual Look") { center.restoreBase() }
        } else if !center.resolution.skipped.isEmpty {
            Button("Bring Back") { center.resumeToday() }
        } else if let waiting = center.waitingForIcons, case .failed = waiting.state {
            Button("Retry") { center.fetchIcons(for: waiting.event.id) }
        }
    }
}

#if DEBUG
#Preview("Celebrations - Showing") {
    DSPreviewPair { CelebrationPreviewGallery(.showing).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Home only") {
    DSPreviewPair { CelebrationPreviewGallery(.homeOnly).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Skipped") {
    DSPreviewPair { CelebrationPreviewGallery(.skipped).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Waiting") {
    DSPreviewPair { CelebrationPreviewGallery(.waiting).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Failed") {
    DSPreviewPair { CelebrationPreviewGallery(.failed).settingsPreviewPage() }.environment(SettingsPresentation())
}
#Preview("Celebrations - Nothing chosen") {
    DSPreviewPair { CelebrationPreviewGallery(.empty).settingsPreviewPage() }.environment(SettingsPresentation())
}
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
