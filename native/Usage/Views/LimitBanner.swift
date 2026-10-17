import SwiftUI

/// A provider's usage limit as it applies to one session: what was hit and when it resets, in
/// Native's one wording, with Resume at Reset and Snooze Until Reset where they make sense.
struct LimitBanner: View {
    let notice: LimitNotice
    var onResumeAtReset: () -> Void = {}
    var onCancelResume: () -> Void = {}
    var onSnooze: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        // The countdown in the detail moves on its own.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            UsageBannerRow(systemImage: systemImage, tint: tint, title: notice.limit.headline, detail: notice.detail(now: context.date)) {
                actions
            }
            .help(notice.limit.message ?? "")
        }
    }

    private var systemImage: String {
        switch (notice.kind, notice.resume) {
        case (_, .scheduled): "clock.arrow.circlepath"
        case (.warning, _): "gauge.with.dots.needle.67percent"
        case (.reached, _): "hourglass"
        case (.snoozed, _): "moon.zzz"
        }
    }

    private var tint: Color {
        switch (notice.kind, notice.resume) {
        case (_, .scheduled): .dsInfo
        case (.warning, _): .dsWarning
        case (.reached, _): .dsDanger
        case (.snoozed, _): .dsTextTertiary
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch notice.resume {
        case .scheduled:
            Button("Cancel Resume", action: onCancelResume)
                .buttonStyle(.ds(.ghost))
        case .offered:
            if notice.kind == .reached {
                Button("Snooze Until Reset", action: onSnooze)
                    .buttonStyle(.ds(.ghost))
                    .help("No more alerts about this limit; one notification when it resets")
            }
            Button("Resume at Reset", action: onResumeAtReset)
                .buttonStyle(.ds(.secondary))
                .help("Sends “\(LimitedWork.continuationPrompt)” or your unsent message when the limit resets")
        case .notNeeded where notice.kind != .snoozed:
            Button("Snooze Until Reset", action: onSnooze)
                .buttonStyle(.ds(.ghost))
            IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
        case .notNeeded, .unavailable:
            IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
        }
    }
}
