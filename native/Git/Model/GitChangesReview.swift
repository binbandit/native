import ACP
import Foundation
import Git
import Observation

/// What one task's changes inspector shows: the scope, and for This Turn, which turn. The session
/// view keeps one, so the files-changed card's Review can point the inspector at its turn.
@Observable
final class GitChangesReview {
    /// The inspector opens on the uncommitted changes (⌘⇧D, docs/keyboard.md); Review switches it.
    var scope = GitChangesScope.uncommitted
    /// The turn This Turn shows, as of the last time it was asked for.
    private(set) var turn: GitTurnReviewTarget?
    /// A file the card asked to see, by the path the card lists; selected once the turn's changes
    /// are in.
    var requestedFile: String?
    /// What the latest turn changed as git sees it, for the files-changed card; nil until worked out,
    /// or when the turn's start wasn't recorded (the card then lists the agent's reported edits).
    private(set) var latestTurnChanges: TurnDetectedChanges?

    /// Shows the session's latest turn, and with `file`, that file's changes in it.
    func showTurn(of session: SessionModel, file: String? = nil) {
        turn = GitTurnReviewTarget(latestTurnOf: session, detected: latestTurnChanges)
        requestedFile = file
        scope = .turn
    }

    /// Keeps This Turn on the latest turn as the agent starts and ends turns.
    func followLatestTurn(of session: SessionModel) {
        guard scope == .turn,
            let latest = GitTurnReviewTarget(latestTurnOf: session, detected: latestTurnChanges), latest != turn
        else { return }
        turn = latest
    }

    /// Works out what the session's latest turn changed, from its recorded start to the working tree
    /// now, once it has ended: the files the agent reported editing with git's counts, then every
    /// other file that changed (a shell command's edits). Reported edits git doesn't show (outside
    /// the repository, or undone since) keep the agent's counts.
    func detectLatestTurnChanges(
        of session: SessionModel, in repository: Repository?, baselines: GitTurnBaselines
    ) async {
        guard session.phase != .prompting, !session.isRestoringHistory,
            let target = GitTurnReviewTarget(latestTurnOf: session),
            let startedAt = target.startedAt,
            let baseline = baselines.baseline(of: target.session, startedAt: startedAt),
            let repository, baseline.root == repository.root.path(percentEncoded: false),
            (try? await repository.hasObject(baseline.snapshot.tree)) == true,
            let now = await GitTurnBaselines.snapshot(of: repository),
            let changes = try? await repository.treeChanges(from: baseline.snapshot.tree, to: now.tree)
        else {
            if !Task.isCancelled { latestTurnChanges = nil }
            return
        }
        guard !Task.isCancelled, session.phase != .prompting,
            GitTurnReviewTarget(latestTurnOf: session) == target
        else { return }
        let root = repository.root
        let observed = changes.map { change in
            TurnSummary.ChangedFile(
                path: root.appending(path: change.path).path(percentEncoded: false),
                added: change.stats?.additions ?? 0, removed: change.stats?.deletions ?? 0)
        }
        let renamed = Dictionary(
            changes.filter { $0.kind == .renamed }.compactMap { change in
                change.originalPath.map { ($0, change.path) }
            }, uniquingKeysWith: { _, last in last })
        let files = TurnSummary.ChangedFile.merging(reported: target.editedFiles, detected: observed) { path in
            let relative = target.relativePath(of: path, root: root) ?? path
            return renamed[relative] ?? relative
        }
        let detected = TurnDetectedChanges(startedAt: startedAt, files: files)
        if latestTurnChanges != detected {
            latestTurnChanges = detected
            followLatestTurn(of: session)
        }
    }

    /// The inspector closed: it opens again on the uncommitted changes.
    func reset() {
        scope = .uncommitted
        requestedFile = nil
    }
}
