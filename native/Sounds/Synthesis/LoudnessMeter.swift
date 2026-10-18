import Accelerate
import Foundation

/// Loudness as ears hear it, so a low sound and a bright one set to the same level feel equally
/// loud: the mean square after ITU-R BS.1770's K-weighting (a high shelf, since we're more
/// sensitive to presence frequencies, and a gentle low cut), in dB. Plain RMS would make
/// higher-pitched sounds seem louder than lower ones at the same number.
nonisolated struct LoudnessMeter: Sendable {
    let sampleRate: Double

    /// The loudness of the first `window` seconds of `left` and `right` (silence counts too, so
    /// short sounds and long ones are compared over the same span).
    func loudness(left: [Float], right: [Float], window: Double) -> Double {
        let count = min(Int(window * sampleRate), left.count)
        guard count > 0 else { return -.infinity }
        let channels = [left, right].map { channel in
            var samples = Array(channel.prefix(count)).map(Double.init)
            for stage in Self.stages(sampleRate: sampleRate) {
                samples = stage.filter(samples)
            }
            return vDSP.sumOfSquares(samples) / Double(Int(window * sampleRate))
        }
        // BS.1770 sums the channels' powers; halving that keeps a centered sound at the same level
        // as its mono version.
        return 10 * log10(max((channels[0] + channels[1]) / 2, .leastNonzeroMagnitude))
    }

    /// The two K-weighting biquads, designed for any sample rate (the standard's constants).
    private static func stages(sampleRate: Double) -> [Biquad] {
        let shelfK = tan(Double.pi * 1_681.974_450_955_533 / sampleRate)
        let shelfQ = 0.707_175_236_955_419_6
        let gain = pow(10, 3.999_843_853_973_347 / 20)
        let gainB = pow(gain, 0.499_666_774_154_541_6)
        let shelfA0 = 1 + shelfK / shelfQ + shelfK * shelfK
        let shelf = Biquad(
            b0: (gain + gainB * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
            b1: 2 * (shelfK * shelfK - gain) / shelfA0,
            b2: (gain - gainB * shelfK / shelfQ + shelfK * shelfK) / shelfA0,
            a1: 2 * (shelfK * shelfK - 1) / shelfA0,
            a2: (1 - shelfK / shelfQ + shelfK * shelfK) / shelfA0
        )
        let lowK = tan(Double.pi * 38.135_470_876_024_44 / sampleRate)
        let lowQ = 0.500_327_037_323_877_3
        let lowA0 = 1 + lowK / lowQ + lowK * lowK
        let lowCut = Biquad(
            b0: 1, b1: -2, b2: 1,
            a1: 2 * (lowK * lowK - 1) / lowA0,
            a2: (1 - lowK / lowQ + lowK * lowK) / lowA0
        )
        return [shelf, lowCut]
    }

    private struct Biquad {
        let b0, b1, b2, a1, a2: Double

        func filter(_ input: [Double]) -> [Double] {
            var output = [Double](repeating: 0, count: input.count)
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for (i, x) in input.enumerated() {
                let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                output[i] = y
                x2 = x1
                x1 = x
                y2 = y1
                y1 = y
            }
            return output
        }
    }
}
