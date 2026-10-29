/// Records each task turn's starting point in its working tree as the turn begins
/// (`GitTurnBaselines`), so the changes inspector's This Turn can show what the turn changed.
@MainActor
enum GitTurnWiring {
    static func connect(_ git: GitStore, to model: AppModel) {
        model.sessionHooks.turnStarted = { session, startedAt in
            // A subagent works in its task's folder; the task's own turn covers what it changes.
            guard !session.isSubagent, !session.isProjectless else { return }
            git.recordTurnStart(of: session.key, at: startedAt, in: session.cwd)
        }
    }
}
