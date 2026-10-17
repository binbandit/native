import ACP
import SwiftUI

extension View {
    /// Rescans the session's working folder when its agent ends a turn or finishes a tool call
    /// that may have written files. The file watcher usually notices first; this catches writes
    /// it coalesced away, and settles the counts the moment the agent stops.
    func refreshesGitStatus(of session: SessionModel, in store: GitStore) -> some View {
        modifier(SessionGitRefresh(session: session, store: store))
    }
}

private struct SessionGitRefresh: ViewModifier {
    let session: SessionModel
    let store: GitStore

    func body(content: Content) -> some View {
        content
            .onChange(of: session.phase) { old, _ in
                if old == .prompting { store.refresh(folder: session.cwd) }
            }
            .onChange(of: finishedWrites) {
                store.refresh(folder: session.cwd)
            }

    }

    /// Completed tool calls of the kinds that touch files.
    private var finishedWrites: Int {
        session.state.items.reduce(0) { count, item in
            guard case .toolCall(let call) = item, call.status == .completed else { return count }
            switch call.kind {
            case .edit, .delete, .move, .execute: return count + 1
            default: return count
            }
        }
    }
}
