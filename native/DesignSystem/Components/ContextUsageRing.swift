import SwiftUI

/// How much of the model's context window a session has used, as a small ring (Conductor's
/// `ProgressRing`: butt-capped stroke on a border-colored track, gray until 90%, then red).
/// Conductor shows it once usage passes 70%; that threshold is the caller's call.
public struct ContextUsageRing: View {
    let fraction: Double
    let size: CGFloat

    /// - Parameters:
    ///   - fraction: Used share of the context window, 0...1.
    ///   - size: Diameter; 12pt fits task rows, Conductor's composer uses 18pt.
    public init(fraction: Double, size: CGFloat = 12) {
        self.fraction = fraction
        self.size = size
    }

    private var clamped: Double { min(max(fraction, 0), 1) }
    private var percent: Int { Int((clamped * 100).rounded()) }
    /// Conductor's 3pt stroke at 18pt, scaled.
    private var lineWidth: CGFloat { max(size / 6, 1.5) }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.dsBorder, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    clamped > 0.9 ? Color.dsDanger : .dsTextTertiary,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .animation(.dsQuick, value: clamped)
        .help("\(percent)% of context used")
        .accessibilityElement()
        .accessibilityLabel("Context used")
        .accessibilityValue("\(percent) percent")
    }
}

#Preview("Context usage") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            ContextUsageRing(fraction: 0.35)
            ContextUsageRing(fraction: 0.75)
            ContextUsageRing(fraction: 0.95)
            ContextUsageRing(fraction: 0.82, size: 18)
        }
    }
}
