import Foundation
import Observation

/// What one task's changes inspector shows: the scope, and for This Turn, which turn. The session
/// view keeps one, so the files-changed card's Review can point the inspector at its turn.
@Observable
final class GitChangesReview {
    /// This Turn and Branch, and recording where each turn begins, while they're being verified:
    /// off unless Native is launched with `-gitTurnReview YES`, which leaves today's inspector.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "gitTurnReview")
    }

    /// The inspector opens on the uncommitted changes (⌘⇧D, docs/keyboard.md); Review switches it.
    var scope = GitChangesScope.uncommitted
    /// The turn This Turn shows, as of the last time it was asked for.
    private(set) var turn: GitTurnReviewTarget?
    /// A file the card asked to see, by the path the card lists; selected once the turn's changes
    /// are in.
    var requestedFile: String?

    /// Shows the session's latest turn, and with `file`, that file's changes in it.
    func showTurn(of session: SessionModel, file: String? = nil) {
        turn = GitTurnReviewTarget(latestTurnOf: session)
        requestedFile = file
        scope = .turn
    }

    /// Keeps This Turn on the latest turn as the agent starts and ends turns.
    func followLatestTurn(of session: SessionModel) {
        guard scope == .turn, let latest = GitTurnReviewTarget(latestTurnOf: session), latest != turn else { return }
        turn = latest
    }

    /// The inspector closed: it opens again on the uncommitted changes.
    func reset() {
        scope = .uncommitted
        requestedFile = nil
    }
}
