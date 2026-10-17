import SwiftUI

/// A usage limit above the composer or in a pane, on `NoticeBanner`: exact numbers and the reset
/// time, what happens to interrupted work, and one primary action. The countdown keeps itself
/// current.
public struct LimitBanner: View {
    let status: LimitStatus
    let onResume: (() -> Void)?
    let onCancelResume: (() -> Void)?
    let onSnooze: (() -> Void)?
    let onDismiss: (() -> Void)?

    /// - Parameters:
    ///   - onResume: Schedules a resume at the reset, offered while `status.resume` is `.offered`.
    ///   - onCancelResume: Cancels a scheduled resume.
    ///   - onSnooze: Quiets the limit until it resets.
    public init(
        status: LimitStatus,
        onResume: (() -> Void)? = nil,
        onCancelResume: (() -> Void)? = nil,
        onSnooze: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.status = status
        self.onResume = onResume
        self.onCancelResume = onCancelResume
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
    }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            NoticeBanner(
                tone: status.level == .reached ? .danger : .warning,
                systemImage: status.level == .reached ? "exclamationmark.octagon" : "gauge.with.dots.needle.67percent",
                title: status.headline,
                detail: detail(now: context.date),
                footnote: status.message
            ) {
                actions
            }
            .accessibilityLabel(status.line(now: context.date))
        }
    }

    /// The reset and, when work was interrupted, what happens to it.
    private func detail(now: Date) -> String? {
        let reset = status.resetText(now: now).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let text = [reset, status.resumeText(now: now)].compactMap(\.self).joined(separator: ". ")
        return text.isEmpty ? nil : text
    }

    @ViewBuilder private var actions: some View {
        switch status.resume {
        case .offered:
            if let onResume {
                Button("Resume When It Resets", action: onResume)
                    .buttonStyle(.ds(.primary))
            }
        case .scheduled:
            if let onCancelResume {
                Button("Cancel Resume", action: onCancelResume)
                    .buttonStyle(.ds(.secondary))
            }
        case .notNeeded, .unavailable:
            if let onSnooze, !status.isSnoozed {
                Button("Snooze Until Reset", action: onSnooze)
                    .buttonStyle(.ds(.secondary))
            }
        }
        if let onDismiss {
            IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
        }
    }
}

#Preview("Limit banner") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            ForEach(GalleryFixtures.limits) { status in
                LimitBanner(status: status, onResume: {}, onCancelResume: {}, onSnooze: {}, onDismiss: {})
            }
        }
        .frame(width: 560)
    }
}
