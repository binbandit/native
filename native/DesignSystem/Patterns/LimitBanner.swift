import SwiftUI

/// A usage limit above the composer or in a pane: exact numbers and the reset time, what happens to
/// interrupted work, and one primary action. The countdown keeps itself current.
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

    private var tone: Color {
        status.level == .reached ? .dsDanger : .dsWarning
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        TimelineView(.everyMinute) { context in
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: status.level == .reached ? "exclamationmark.octagon" : "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13))
                    .foregroundStyle(tone)
                    .frame(width: DS.Size.rowLeading, height: 18)

                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(status.headline)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    if let detail = detail(now: context.date) {
                        Text(detail)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                    }
                    if let message = status.message {
                        Text(message)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                .tracking(DS.Tracking.tight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                actions
            }
            .padding(.vertical, DS.Space.md)
            .padding(.horizontal, DS.Space.lg)
            .background(.dsSurfaceRaised, in: shape)
            .overlay { shape.strokeBorder(tone.opacity(0.35), lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(status.line(now: context.date))
        }
    }

    /// The reset and, when work was interrupted, what happens to it.
    private func detail(now: Date) -> String? {
        let parts = [status.resetText(now: now).map { $0.prefix(1).uppercased() + $0.dropFirst() }, status.resumeText(now: now)]
        let text = parts.compactMap(\.self).joined(separator: ". ")
        return text.isEmpty ? nil : text
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: DS.Space.xs) {
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
