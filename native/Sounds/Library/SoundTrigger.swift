/// The moments Native can play a sound for.
nonisolated enum SoundTrigger: String, CaseIterable, Identifiable, Sendable {
    case taskFinished
    case approvalNeeded
    case limitReached

    var id: String { rawValue }

    var title: String {
        switch self {
        case .taskFinished: "Task finished"
        case .approvalNeeded: "Approval needed"
        case .limitReached: "Limit reached"
        }
    }

    var detail: String {
        switch self {
        case .taskFinished: "An agent finishes working on a task."
        case .approvalNeeded: "An agent is waiting for you to allow a tool call."
        case .limitReached: "An agent stops at its token or turn limit, or hits a usage limit."
        }
    }
}
