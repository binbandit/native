import Accelerate
import Foundation

/// Renders a `Score` of struck notes: additive synthesis with an independent decay per partial
/// (high partials die first, as on real bars and bells), then `ConvolutionReverb`. Deterministic,
/// so a sound renders the same every time and listening tests hear exactly what ships.
nonisolated struct ChimeSynthesizer: Sendable {
    /// One mode of vibration of a struck note.
    struct Partial: Sendable {
        /// Frequency as a multiple of the note's.
        var ratio: Double
        /// dB relative to the note.
        var level: Double
        /// Seconds to fall 60 dB.
        var t60: Double
        /// A second mode this many Hz above, for the slow beating real bells and glass have.
        var twin: Double = 0
        var twinLevel: Double = -120
    }

    /// One struck note.
    struct Strike: Sendable {
        var time: Double
        var frequency: Double
        /// dB.
        var level: Double
        /// -1 (left) to 1 (right).
        var pan: Double
        var partials: [Partial]
        /// Raised-cosine rise time. A few milliseconds reads as a soft mallet and never clicks.
        var attack: Double
        /// Scales every partial's decay, so a passing note can be shorter than the one it leads to.
        var t60Scale: Double = 1
        /// dB of the mallet's contact noise: a brief filtered burst that makes the strike physical.
        var contact: Double = -120
        /// Lowpass corner of that noise in Hz; darker reads as softer.
        var contactBrightness: Double = 4_000
    }

    struct Room: Sendable {
        var t60: Double
        var predelay: Double
        /// Reverb level in dB relative to the dry signal's energy.
        var wet: Double
        /// Lowpass corner of the reverb's start in Hz; it darkens as it decays.
        var brightness: Double
    }

    struct Score: Sendable {
        var strikes: [Strike]
        var room: Room
    }

    /// Every sound's loudness: `LoudnessMeter` over its first 600ms. Set so that at the default 0.7
    /// volume Native's sounds are as loud as the reference app plays its chime (its file at a fixed 0.5
    /// gain), and switching sounds never jumps in level.
    static let loudness = -20.2
    static let loudnessWindow = 0.6
    /// Headroom kept whatever the loudness asks for.
    static let peakCeiling = -3.0

    let sampleRate: Double

    func render(_ score: Score) -> RenderedSound {
        let ring = score.strikes.map { $0.time + ($0.partials.map(\.t60).max() ?? 1) * $0.t60Scale }.max() ?? 1
        // Past three seconds nothing is audible; the room needs a little longer to settle.
        let length = Int((min(ring, 3) + score.room.t60 * 0.5) * sampleRate)
        var left = [Float](repeating: 0, count: length)
        var right = [Float](repeating: 0, count: length)
        var noise = SeededNoise(seed: 0x4E41_5449_5645)
        for strike in score.strikes {
            add(strike, toLeft: &left, right: &right, noise: &noise)
        }
        ConvolutionReverb(room: score.room, sampleRate: sampleRate).apply(left: &left, right: &right)
        finish(left: &left, right: &right)
        return RenderedSound(sampleRate: sampleRate, left: left, right: right)
    }

    private func add(_ strike: Strike, toLeft left: inout [Float], right: inout [Float], noise: inout SeededNoise) {
        let start = Int(strike.time * sampleRate)
        let count = left.count - start
        guard count > 0 else { return }
        // Vectorized in Double: phases run to tens of thousands of radians, where Float loses the
        // precision a pure tone needs, and Accelerate keeps Debug builds fast.
        let time = vDSP.ramp(withInitialValue: 0.0, increment: 1.0, count: count)
        var tone = [Double](repeating: 0, count: count)
        for partial in strike.partials {
            let frequency = strike.frequency * partial.ratio
            // Past Nyquist a partial folds back as an unrelated, unpleasant pitch.
            guard frequency < sampleRate * 0.45 else { continue }
            var wave = vDSP.multiply(Self.amplitude(decibels: partial.level), vForce.sin(vDSP.multiply(2 * .pi * frequency / sampleRate, time)))
            if partial.twin != 0 {
                let twinStep = 2 * .pi * (frequency + partial.twin) / sampleRate
                wave = vDSP.add(wave, vDSP.multiply(Self.amplitude(decibels: partial.twinLevel), vForce.sin(vDSP.multiply(twinStep, time))))
            }
            let decay = vForce.exp(vDSP.multiply(-6.907_755 / (partial.t60 * strike.t60Scale * sampleRate), time))
            tone = vDSP.add(tone, vDSP.multiply(wave, decay))
        }
        var note = vDSP.doubleToFloat(tone)
        addContact(of: strike, to: &note, noise: &noise)
        let attack = max(Int(strike.attack * sampleRate), 1)
        for i in 0..<min(attack, count) {
            note[i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(attack)))
        }
        // Equal-power pan, unity in the center.
        let gain = Self.amplitude(decibels: strike.level)
        let angle = (strike.pan + 1) * Double.pi / 4
        let leftGain = Float(gain * cos(angle) * 2.squareRoot())
        let rightGain = Float(gain * sin(angle) * 2.squareRoot())
        for i in 0..<count {
            left[start + i] += note[i] * leftGain
            right[start + i] += note[i] * rightGain
        }
    }

    private func addContact(of strike: Strike, to note: inout [Float], noise: inout SeededNoise) {
        guard strike.contact > -100 else { return }
        let length = min(Int(0.012 * sampleRate), note.count)
        let coefficient = Float(exp(-2 * Double.pi * strike.contactBrightness / sampleRate))
        // Lowpassed uniform noise loses most of its level; this brings it back to `contact`.
        let amplitude = Float(Self.amplitude(decibels: strike.contact)) * 4
        var state: Float = 0
        for i in 0..<length {
            let envelope = Float(exp(-Double(i) / (0.0025 * sampleRate)))
            state = coefficient * state + (1 - coefficient) * noise.nextSignal()
            note[i] += state * envelope * amplitude
        }
    }

    /// Sets the loudness, trims what's inaudible and fades the end so nothing is cut mid-ring.
    private func finish(left: inout [Float], right: inout [Float]) {
        let measured = LoudnessMeter(sampleRate: sampleRate).loudness(left: left, right: right, window: Self.loudnessWindow)
        let peak = max(vDSP.maximumMagnitude(left), vDSP.maximumMagnitude(right), .leastNonzeroMagnitude)
        let scale = Float(min(
            Self.amplitude(decibels: Self.loudness - measured),
            Self.amplitude(decibels: Self.peakCeiling) / Double(peak)
        ))
        left = vDSP.multiply(scale, left)
        right = vDSP.multiply(scale, right)
        let floor = Float(Self.amplitude(decibels: -72))
        var end = left.count
        while end > 1, abs(left[end - 1]) < floor, abs(right[end - 1]) < floor {
            end -= 1
        }
        left.removeSubrange(end...)
        right.removeSubrange(end...)
        let fade = min(Int(0.12 * sampleRate), end)
        for i in 0..<fade {
            let gain = Float(0.5 + 0.5 * cos(Double.pi * Double(i) / Double(fade)))
            left[end - fade + i] *= gain
            right[end - fade + i] *= gain
        }
    }

    /// Linear gain for a level in dB.
    static func amplitude(decibels level: Double) -> Double {
        pow(10, level / 20)
    }
}
