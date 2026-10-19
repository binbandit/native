import SwiftUI

/// Elapsed work time in `DSFormat.duration`'s form with tabular figures: a clock that ticks every
/// second while the work runs (`end` nil) and a fixed total once it's done. Running clocks share
/// `DSSecondClock`, so each costs a redraw of its own label once a second and nothing else.
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
            ElapsedTimeLabel(seconds: end.timeIntervalSince(start))
        } else {
            RunningElapsedTime(start: start)
        }
    }
}

/// Reads the shared clock in its own body, so a tick redraws this label and not its container.
private struct RunningElapsedTime: View {
    let start: Date

    var body: some View {
        ElapsedTimeLabel(seconds: DSSecondClock.shared.now.timeIntervalSince(start))
            .task { await DSSecondClock.shared.hold() }
    }
}

private struct ElapsedTimeLabel: View {
    let seconds: TimeInterval

    var body: some View {
        Text(DSFormat.duration(seconds))
            .monospacedDigit()
            .accessibilityLabel(
                Duration.seconds(Int(max(seconds, 0))).formatted(
                    .units(allowed: [.hours, .minutes, .seconds], width: .wide)))
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
