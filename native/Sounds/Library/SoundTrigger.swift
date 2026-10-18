/// The moments Native plays a sound for, one per meaning, each with its own sound by default so
/// the user can tell them apart without looking.
nonisolated enum SoundTrigger: String, CaseIterable, Identifiable, Sendable {
    case taskFinished
    case needsYou
    case wentWrong

    var id: String { rawValue }

    /// Reads a stored trigger, including the ones earlier versions saved: approvals became
    /// "needs you" and limits became "went wrong".
    init?(storedValue: String) {
        switch storedValue {
        case "approvalNeeded": self = .needsYou
        case "limitReached": self = .wentWrong
        default: self.init(rawValue: storedValue)
        }
    }

    var title: String {
        switch self {
        case .taskFinished: "Task finished"
        case .needsYou: "Needs you"
        case .wentWrong: "Something went wrong"
        }
    }

    var detail: String {
        switch self {
        case .taskFinished: "An agent finished its turn."
        case .needsYou: "An agent asks permission or a question, a plan or workflow step waits for approval, or a goal is blocked."
        case .wentWrong: "A turn failed or hit a limit, an agent stopped or couldn't start, or a workflow step failed."
        }
    }

    /// Which sound wins when several moments come at once: trouble, then a request, then news.
    var urgency: Int {
        switch self {
        case .taskFinished: 0
        case .needsYou: 1
        case .wentWrong: 2
        }
    }

    var defaultSound: SoundID {
        switch self {
        case .taskFinished: .native(.chime)
        case .needsYou: .native(.nudge)
        case .wentWrong: .native(.fall)
        }
    }
}
