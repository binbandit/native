import AppAppearance
import SwiftUI

extension EnvironmentValues {
    /// Set at a task boundary so its sidebar and transcript share the model's saved choice.
    @Entry var dsWorkingAnimation: WorkingAnimation? = nil
}

extension DotGridLoader.Pattern {
    /// Seven calm variations, all on the same nine positions and a 2.4-second loop.
    nonisolated static func workingTiming(_ animation: WorkingAnimation) -> Timing {
        let delays: [Double?]
        let rise: Double
        let fall: Double
        switch animation {
        case .sweep:
            delays = [0, 24, 48, 0, 24, 48, 0, 24, 48]
            rise = 24
            fall = 48
        case .ripple:
            delays = [48, 24, 48, 24, 0, 24, 48, 24, 48]
            rise = 24
            fall = 48
        case .orbit:
            delays = [0, 18, 36, 126, nil, 54, 108, 90, 72]
            rise = 18
            fall = 36
        case .rain:
            delays = [0, 48, 24, 24, 72, 48, 48, 96, 72]
            rise = 18
            fall = 36
        case .checkerboard:
            delays = [0, 72, 0, 72, 0, 72, 0, 72, 0]
            rise = 30
            fall = 42
        case .snake:
            delays = [0, 16, 32, 80, 64, 48, 96, 112, 128]
            rise = 16
            fall = 32
        case .breathe:
            delays = Array(repeating: 0, count: 9)
            rise = 60
            fall = 84
        }
        return Timing(
            start: 0, end: 144,
            dots: delays.enumerated().map { index, delay in
                // Adjacent cycles keep pulses crossing the loop boundary continuous.
                let pulses: [(Double, Double, Double)] =
                    delay.map { delay in
                        [-144.0, 0, 144].map { offset in
                            let start = delay + offset
                            return (start, start + rise, start + rise + fall)
                        }
                    } ?? []
                return Dot(x: 50 + Double(index % 3) * 70, y: 50 + Double(index / 3) * 70, pulses: pulses)
            })
    }
}
