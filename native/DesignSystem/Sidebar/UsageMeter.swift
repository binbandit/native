import SwiftUI

/// A usage limit as the reference app draws it (`UsageProgressRow`, `ProgressBar`): label and percentage over
/// an 8pt bar that turns from the accent to warning at 80% and to error at 100%, with an optional
/// reset time.
public struct UsageMeter: View {
    let title: String
    let fraction: Double
    let detail: String?

    /// - Parameters:
    ///   - fraction: Used share of the limit; values past 1 read as 100%.
    ///   - detail: Trailing detail, e.g. "Resets in 2h 14m".
    public init(title: String, fraction: Double, detail: String? = nil) {
        self.title = title
        self.fraction = fraction
        self.detail = detail
    }

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var percent: Int { Int((max(fraction, 0) * 100).rounded()) }

    private var fill: Color {
        if fraction >= 1 {
            .dsDangerMeterFill
        } else if fraction >= 0.8 {
            .dsWarningFill
        } else {
            .dsAccent
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.md) {
                Text(title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Text("\(percent)%")
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
                Spacer(minLength: 0)
                if let detail {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .medium))
                        Text(detail)
                            .font(.dsCaption)
                    }
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                }
            }
            .tracking(DS.Tracking.tight)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.dsSelected)
                    Rectangle()
                        .fill(fill)
                        .frame(width: proxy.size.width * clamped)
                }
            }
            .frame(height: 8)
            .clipShape(.rect(cornerRadius: DS.Radius.small))
            .animation(.dsQuick, value: clamped)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(["\(percent) percent", detail].compactMap(\.self).joined(separator: ", "))
    }
}

#Preview("Usage meter") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            UsageMeter(title: "Usage", fraction: 0.42, detail: "Resets in 2h 14m")
            UsageMeter(title: "Weekly", fraction: 0.86)
            UsageMeter(title: "Monthly", fraction: 1.2, detail: "Resets Nov 1")
        }
        .frame(width: 232)
    }
}
