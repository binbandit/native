import SwiftUI

/// A compact age that keeps itself current: "now", "5m", "3h", "4d", "2mo", "1y", in 10pt
/// tertiary. It reads `DSMinuteClock`, so ages move on together once a minute, and not while the
/// app can't be seen.
public struct CompactAgeText: View {
    let date: Date

    public init(date: Date) {
        self.date = date
    }

    public var body: some View {
        Text(DSFormat.compactAge(date, now: DSMinuteClock.shared.now))
            .font(.dsMicro)
            .monospacedDigit()
            .foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.xs)
            .accessibilityLabel(date.formatted(.relative(presentation: .named)))
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
