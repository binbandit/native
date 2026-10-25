import SwiftUI

/// How long an ask has waited ("now", "6m"), in the attention color, beside the ask wherever it's
/// shown: a sidebar row, Peek's header, the well. It reads the shared minute clock.
public struct TaskAttentionClock: View {
    let since: Date

    public init(since: Date) {
        self.since = since
    }

    public var body: some View {
        DSMinuteTimeline { now in
            Text(DSFormat.compactAge(since, now: now))
                .font(DS.Sidebar.clockFont)
                .monospacedDigit()
                .foregroundStyle(.dsAttention)
        }
        .fixedSize()
    }
}

#if DEBUG
#Preview("Attention clock - Now, minutes and hours") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            TaskAttentionClock(since: .now)
            TaskAttentionClock(since: .now.addingTimeInterval(-360))
            TaskAttentionClock(since: .now.addingTimeInterval(-3 * 3600))
        }
        .padding(DS.Space.lg)
    }
}
#endif
