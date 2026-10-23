/// The playful variations of Native's working dot grid. The design system owns their motion.
public enum WorkingAnimation: String, CaseIterable, Codable, Sendable {
    case sweep, ripple, orbit, rain, checkerboard, snake, breathe

    public var title: String {
        switch self {
        case .sweep: "Sweep"
        case .ripple: "Ripple"
        case .orbit: "Orbit"
        case .rain: "Rain"
        case .checkerboard: "Checkerboard"
        case .snake: "Snake"
        case .breathe: "Breathe"
        }
    }
}
