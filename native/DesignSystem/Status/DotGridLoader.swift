import SwiftUI

/// Conductor's dot-grid loaders: a 3x3 grid of dots that pop in and out in sequence. The patterns
/// and timings are read from its Lottie files (240pt canvas, dots 40pt across at 50/120/190, 60fps),
/// so `typing` is "grid-inorder", `waiting` "grid-slow-interpolation" and `settingUp` "grid-bloom".
/// Draws in the foreground style; with Reduce Motion it holds a still grid.
public struct DotGridLoader: View {
    public enum Pattern: Sendable {
        case typing, waiting, settingUp
    }

    let pattern: Pattern

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pattern: Pattern) {
        self.pattern = pattern
    }

    public var body: some View {
        if reduceMotion {
            canvas(frame: nil)
        } else {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let timing = pattern.timing
                let loop = (timing.end - timing.start) / 60
                let frame = timing.start + elapsed.truncatingRemainder(dividingBy: loop) * 60
                canvas(frame: frame)
            }
        }
    }

    private func canvas(frame: Double?) -> some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 240
            for dot in pattern.timing.dots {
                // A still grid shows every dot at 60%.
                let scale = frame.map { dot.scale(at: $0) } ?? 0.6
                guard scale > 0.01 else { continue }
                let radius = 20 * scale * unit
                let rect = CGRect(
                    x: dot.x * unit - radius, y: dot.y * unit - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

extension DotGridLoader.Pattern {
    nonisolated struct Timing: Sendable {
        let start: Double
        let end: Double
        let dots: [Dot]
    }

    /// One dot: its center on the 240pt canvas and its pulses, each (rise start, peak, fall end)
    /// in frames.
    nonisolated struct Dot: Sendable {
        let x: Double
        let y: Double
        let pulses: [(Double, Double, Double)]

        // Lottie's curves: a quick rise, then a slow start into the fall.
        private static let rise = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.167, y: 0.177),
            endControlPoint: UnitPoint(x: 0.1, y: 1)
        )
        private static let fall = UnitCurve.bezier(
            startControlPoint: UnitPoint(x: 0.9, y: 0),
            endControlPoint: UnitPoint(x: 0.833, y: 0.813)
        )

        func scale(at frame: Double) -> Double {
            for (start, peak, end) in pulses {
                if frame >= start, frame < peak {
                    return Self.rise.value(at: (frame - start) / (peak - start))
                }
                if frame >= peak, frame < end {
                    return 1 - Self.fall.value(at: (frame - peak) / (end - peak))
                }
            }
            return 0
        }
    }

    nonisolated var timing: Timing {
        switch self {
        case .typing: Self.typingTiming
        case .waiting: Self.waitingTiming
        case .settingUp: Self.settingUpTiming
        }
    }

    // Dot positions on the canvas.
    private nonisolated static let low = 50.0, mid = 120.0, high = 190.0

    /// `typing.json`: frames 0-64, column by column.
    private nonisolated static let typingTiming = Timing(
        start: 0, end: 64,
        dots: [
            Dot(x: low, y: low, pulses: [(0, 17, 35)]),
            Dot(x: low, y: mid, pulses: [(5, 22, 38)]),
            Dot(x: low, y: high, pulses: [(9, 25, 41)]),
            Dot(x: mid, y: low, pulses: [(12, 28, 44)]),
            Dot(x: mid, y: mid, pulses: [(15, 31, 47)]),
            Dot(x: mid, y: high, pulses: [(18, 34, 50)]),
            Dot(x: high, y: low, pulses: [(21, 37, 53)]),
            Dot(x: high, y: mid, pulses: [(24, 40, 57)]),
            Dot(x: high, y: high, pulses: [(27, 45, 62)]),
        ])

    /// `waiting.json`: frames 32-128, around the border clockwise; the center stays dark.
    private nonisolated static let waitingTiming = Timing(
        start: 32, end: 128,
        dots: [
            Dot(x: low, y: low, pulses: [(88, 100, 112)]),
            Dot(x: mid, y: low, pulses: [(0, 16, 32), (96, 112, 128)]),
            Dot(x: high, y: low, pulses: [(16, 28, 40), (112, 124, 136)]),
            Dot(x: high, y: mid, pulses: [(24, 40, 56), (120, 136, 152)]),
            Dot(x: high, y: high, pulses: [(40, 52, 64)]),
            Dot(x: mid, y: high, pulses: [(48, 64, 80)]),
            Dot(x: low, y: high, pulses: [(64, 76, 88)]),
            Dot(x: low, y: mid, pulses: [(72, 88, 104)]),
        ])

    /// `setting-up-loader.json`: frames 0-144, blooming out from the center.
    private nonisolated static let settingUpTiming = Timing(
        start: 0, end: 144,
        dots: [
            Dot(x: mid, y: mid, pulses: [(0, 16, 32), (72, 88, 104)]),
            Dot(x: mid, y: low, pulses: [(9, 25, 41), (93, 109, 125)]),
            Dot(x: high, y: mid, pulses: [(13, 29, 45), (89, 105, 121)]),
            Dot(x: mid, y: high, pulses: [(17, 33, 49), (85, 101, 117)]),
            Dot(x: low, y: mid, pulses: [(21, 37, 53), (81, 97, 113)]),
            Dot(x: low, y: low, pulses: [(27, 43, 59), (111, 127, 143)]),
            Dot(x: high, y: low, pulses: [(31, 47, 63), (107, 123, 139)]),
            Dot(x: high, y: high, pulses: [(35, 51, 67), (103, 119, 135)]),
            Dot(x: low, y: high, pulses: [(39, 55, 71), (99, 115, 131)]),
        ])
}

#Preview("Dot grid loaders") {
    DSPreviewPair {
        HStack(spacing: DS.Space.xxl) {
            DotGridLoader(pattern: .typing).frame(width: 48, height: 48)
            DotGridLoader(pattern: .waiting).frame(width: 48, height: 48)
            DotGridLoader(pattern: .settingUp).frame(width: 48, height: 48)
        }
        .foregroundStyle(.dsTextPrimary)
    }
}
