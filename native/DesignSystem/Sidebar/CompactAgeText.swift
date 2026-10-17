import SwiftUI

/// A compact age that keeps itself current: "now", "5m", "3h", "4d", "2mo", "1y" (Conductor's and
/// Factory's sidebar ages), in 10pt tertiary.
public struct CompactAgeText: View {
    let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            Text(DSFormat.compactAge(date, now: context.date))
                .font(.dsMicro)
                .monospacedDigit()
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.xs)
                .accessibilityLabel(date.formatted(.relative(presentation: .named)))
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
