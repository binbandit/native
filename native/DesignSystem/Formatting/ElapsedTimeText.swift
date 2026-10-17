import SwiftUI

/// Elapsed work time in `DSFormat.duration`'s form with tabular figures: a clock that ticks every
/// second while the work runs (`end` nil) and a fixed total once it's done.
///
///     ElapsedTimeText(since: turn.startedAt, until: turn.finishedAt)
public struct ElapsedTimeText: View {
    let start: Date
    let end: Date?

    public init(since start: Date, until end: Date? = nil) {
        self.start = start
        self.end = end
    }

    public var body: some View {
        if let end {
            label(end.timeIntervalSince(start))
        } else {
            TimelineView(.periodic(from: start, by: 1)) { context in
                label(context.date.timeIntervalSince(start))
            }
        }
    }

    private func label(_ seconds: TimeInterval) -> some View {
        Text(DSFormat.duration(seconds))
            .monospacedDigit()
            .accessibilityLabel(Duration.seconds(Int(max(seconds, 0))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))
    }
}

#Preview("Elapsed time") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ElapsedTimeText(since: .now.addingTimeInterval(-72))
            ElapsedTimeText(since: .now.addingTimeInterval(-3840), until: .now)
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextSecondary)
    }
}
