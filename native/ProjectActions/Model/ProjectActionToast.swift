import Foundation

/// What an action's run did, said where the user is when they can't see it happen: a background
/// run ending, or a terminal run ending out of view. Up to two next steps.
struct ProjectActionToast: Identifiable, Equatable {
    enum Tone {
        case success, failure, info
    }

    struct Step {
        let title: String
        let perform: () -> Void
    }

    let id = UUID()
    let tone: Tone
    let message: String
    var detail: String?
    var steps: [Step] = []

    /// Successes go away on their own; a failure waits a while longer for its next step.
    var duration: Duration {
        tone == .failure ? .seconds(12) : .seconds(5)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
