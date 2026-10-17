import Foundation
import Git

/// Feedback for a git action, shown where the action was taken: what happened, what Native did
/// about it, and the one thing to do next.
struct GitNotice: Identifiable, Equatable {
    enum Tone {
        case success, failure
    }

    /// The next step a notice offers.
    enum Action: Equatable {
        case pull
        case push
        /// Puts discarded files back from the checkpoint saved before discarding.
        case restore(Checkpoint, paths: [String])
        /// Selects the first conflicted file.
        case showConflicts
        /// Takes back the commits a smart commit made.
        case undoCommits(CommitPlanReceipt)

        var title: String {
            switch self {
            case .pull: "Pull"
            case .push: "Try Again"
            case .restore: "Restore"
            case .showConflicts: "Show Conflicts"
            case .undoCommits: "Undo"
            }
        }
    }

    let id = UUID()
    var tone: Tone
    var title: String
    var message: String?
    /// Git's own output, for when the reason is in it (a hook's report, a server's message).
    var detail: String?
    var action: Action?

    static func == (lhs: GitNotice, rhs: GitNotice) -> Bool {
        lhs.id == rhs.id
    }
}
