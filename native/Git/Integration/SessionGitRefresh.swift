import ACP
import Git
import SwiftUI

extension View {
    /// Rescans the session's working folder when its agent ends a turn or finishes a tool call
    /// that may have written files. The file watcher usually notices first; this catches writes
    /// it coalesced away, and settles the counts the moment the agent stops.
    func refreshesGitStatus(of session: SessionModel, in store: GitStore) -> some View {
        modifier(SessionGitRefresh(session: session, store: store))
    }

    /// Works out what the latest turn changed as git sees it whenever a turn ends and when the task
    /// opens (`GitChangesReview.detectLatestTurnChanges`), for the files-changed card.
    func detectsTurnChanges(of session: SessionModel, into review: GitChangesReview, in store: GitStore) -> some View {
        // Resolve through the session's host, as the inspector does, never by the local path alone.
        let repository = session.isProjectless ? nil : store.model(for: session.cwd, session: session.key).repository
        let request = GitTurnDetectionRequest(
            phase: session.phase, isRestoringHistory: session.isRestoringHistory, repository: repository,
            baseline: store.turnBaselines.latestBaseline(of: session.key))
        return task(id: request) {
            guard !session.isProjectless else { return }
            await review.detectLatestTurnChanges(of: session, in: repository, baselines: store.turnBaselines)
        }
    }
}

private struct GitTurnDetectionRequest: Equatable {
    let phase: SessionModel.Phase
    let isRestoringHistory: Bool
    let repository: Repository?
    let baseline: GitTurnBaseline?
}

private struct SessionGitRefresh: ViewModifier {
    let session: SessionModel
    let store: GitStore

    func body(content: Content) -> some View {
        content
            .onChange(of: session.phase) { old, _ in
                if !session.isProjectless, old == .prompting {
                    store.refresh(folder: session.cwd, session: session.key)
                }
            }
            // A mirror, not `state`: this updated with every streamed chunk and counted the whole
            // transcript each time.
            .onChange(of: session.completedWriteCount) {
                guard !session.isProjectless else { return }
                store.refreshWhenSettled(folder: session.cwd, session: session.key)
            }
    }
}
