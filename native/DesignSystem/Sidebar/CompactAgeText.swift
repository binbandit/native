import SwiftUI

/// A compact age that keeps itself current: "now", "5m", "3h", "4d", "2mo", "1y" (the reference app's and
/// the reference app's sidebar ages), in 10pt tertiary.
public struct CompactAgeText: View {
    let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.format(date, now: context.date))
                .font(.dsMicro)
                .monospacedDigit()
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.xs)
                .accessibilityLabel(date.formatted(.relative(presentation: .named)))
        }
    }

    nonisolated static func format(_ date: Date, now: Date) -> String {
        let minutes = Int(max(now.timeIntervalSince(date), 0) / 60)
        let hour = 60, day = 60 * 24
        switch minutes {
        case ..<1: return "now"
        case ..<hour: return "\(minutes)m"
        case ..<day: return "\(minutes / hour)h"
        case ..<(day * 30): return "\(minutes / day)d"
        case ..<(day * 365): return "\(minutes / (day * 30))mo"
        default: return "\(minutes / (day * 365))y"
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
