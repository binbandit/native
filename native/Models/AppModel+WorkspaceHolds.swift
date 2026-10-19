import Foundation

// Holding a folder's sessions while something prepares it (a new worktree's setup script), so the
// agent doesn't start on a checkout that isn't ready. Messages sent meanwhile queue where the user
// can see them, and go out once the hold lifts.
extension AppModel {
    /// Holds the turns of every session in `folder` for `reason`, or with nil lifts the hold and
    /// sends what queued up meanwhile.
    func holdTurns(in folder: URL, because reason: String?) {
        sendGate.setWorkspaceHold(reason, for: folder)
        guard reason == nil else { return }
        for session in sessions.open(in: folder) {
            session.drainQueue()
        }
    }
}
