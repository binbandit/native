import SwiftUI

/// A thin line through recent values, scaled to their own range (Orca's Resource Manager trend).
/// A flat history draws a flat line through the middle.
struct Sparkline: View {
    let values: [UInt64]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let low = values.min(), let high = values.max() else { return }
            let range = Double(high - low)
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (index, value) in values.enumerated() {
                let level = range > 0 ? Double(value - low) / range : 0.5
                let point = CGPoint(x: CGFloat(index) * step, y: size.height * (1 - level))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        .foregroundStyle(.dsTextTertiary)
        .frame(width: StatusBarMetrics.sparklineSize.width, height: StatusBarMetrics.sparklineSize.height)
        .accessibilityHidden(true)
    }
}
