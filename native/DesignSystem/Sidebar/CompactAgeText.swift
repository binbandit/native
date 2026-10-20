import SwiftUI

/// A compact age that keeps itself current: "now", "5m", "3h", "4d", "2mo", "1y", in 10pt
/// tertiary.
public struct CompactAgeText: View {
    let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        if LaunchExperiment.noAgeTimeline {
            label(now: .now)
        } else {
            TimelineView(.everyMinute) { context in
                label(now: context.date)
            }
        }
    }

    private func label(now: Date) -> some View {
        Text(DSFormat.compactAge(date, now: now))
            .font(.dsMicro)
            .monospacedDigit()
            .foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.xs)
            .lxUnless(LaunchExperiment.noAgeA11y) {
                $0.accessibilityLabel(date.formatted(.relative(presentation: .named)))
            }
    }
}

#Preview("Compact age") {
    DSPreviewPair {
        HStack {
            CompactAgeText(date: .now)
            CompactAgeText(date: .now.addingTimeInterval(-300))
            CompactAgeText(date: .now.addingTimeInterval(-3600 * 30))
        }
    }
}
