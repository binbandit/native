import Foundation

/// Native's own notification sounds. They're synthesized rather than shipped as recordings, so
/// they're ours to distribute and cost nothing in the bundle; `ChimeSynthesizer` renders each once
/// on first use.
///
/// All three keep what makes the reference app's chime pleasant (a nearly pure tone that dies away within
/// about a second) and add a character of their own: `chime` is a rising fifth on glass, `soft` a
/// felt mallet on wood, `bell` a small handbell.
nonisolated enum NativeChime: String, CaseIterable, Identifiable, Sendable {
    case chime, soft, bell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chime: "Chime"
        case .soft: "Soft"
        case .bell: "Bell"
        }
    }

    func render(sampleRate: Double = 48_000) -> RenderedSound {
        ChimeSynthesizer(sampleRate: sampleRate).render(score)
    }

    /// The notes, their partials and the room. Partial levels are kept well below the fundamental
    /// so every sound still reads as one soft tone; the overtones only color the attack.
    var score: ChimeSynthesizer.Score {
        switch self {
        case .chime:
            // The second note lands as a resolution, so it's a little louder and rings longer. The
            // 2.756 mode is a struck bar's first overtone: a hint of glass that's gone in 200ms.
            let glass: [ChimeSynthesizer.Partial] = [
                .init(ratio: 1, level: 0, t60: 1.6, twin: 0.7, twinLevel: -21),
                .init(ratio: 2, level: -21, t60: 0.55),
                .init(ratio: 2.756, level: -31, t60: 0.22),
                .init(ratio: 5.404, level: -42, t60: 0.08),
            ]
            return .init(
                strikes: [
                    .init(time: 0, frequency: Pitch.e5, level: -2.5, pan: -0.18, partials: glass, attack: 0.0025, t60Scale: 0.75, contact: -40),
                    .init(time: 0.11, frequency: Pitch.b5, level: 0, pan: 0.18, partials: glass, attack: 0.0025, contact: -40),
                ],
                room: .init(t60: 1.25, predelay: 0.014, wet: -13, brightness: 7_500)
            )
        case .soft:
            // A slower attack and a dark contact read as felt; the marimba's tuned fourth harmonic
            // gives it a woody body without brightness.
            return .init(
                strikes: [
                    .init(
                        time: 0, frequency: Pitch.f5, level: 0, pan: 0,
                        partials: [
                            .init(ratio: 1, level: 0, t60: 1.05),
                            .init(ratio: 3.99, level: -23, t60: 0.16),
                            .init(ratio: 9.8, level: -40, t60: 0.045),
                        ],
                        attack: 0.006, contact: -44, contactBrightness: 2_400
                    ),
                ],
                room: .init(t60: 1.05, predelay: 0.018, wet: -11, brightness: 5_000)
            )
        case .bell:
            // Handbells are tuned to a strong twelfth (3.0); the twin on the fundamental beats
            // about once a second, the slow warble real bells have.
            return .init(
                strikes: [
                    .init(
                        time: 0, frequency: Pitch.a5, level: 0, pan: 0,
                        partials: [
                            .init(ratio: 1, level: 0, t60: 2.2, twin: 1.15, twinLevel: -11),
                            .init(ratio: 2.005, level: -24, t60: 1.0),
                            .init(ratio: 3.01, level: -15, t60: 0.9),
                            .init(ratio: 4.87, level: -30, t60: 0.28),
                            .init(ratio: 7.31, level: -38, t60: 0.1),
                        ],
                        attack: 0.0015, contact: -36, contactBrightness: 6_500
                    ),
                ],
                room: .init(t60: 1.8, predelay: 0.02, wet: -12, brightness: 6_000)
            )
        }
    }
}

/// Equal-tempered pitches, A4 = 440 Hz.
nonisolated private enum Pitch {
    static let e5 = 659.26
    static let f5 = 698.46
    static let a5 = 880.0
    static let b5 = 987.77
}
