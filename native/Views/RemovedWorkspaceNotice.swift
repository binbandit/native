import SwiftUI

/// Above the composer of a task whose worktree was removed outside Native while its work isn't
/// done (`AppModel.removedWorkspaces`): what happened, what's left, and Restore Worktree or Archive.
struct RemovedWorkspaceNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.transcriptColumnMaxWidth) private var columnWidth
    let session: SessionModel

    var body: some View {
        if let removed = model.removedWorkspaces[session.key] {
            let isRestoring = model.restoringRemovedWorkspaces.contains(session.key)
            NoticeBanner(
                tone: .warning, systemImage: "folder.badge.minus", title: "Its worktree was removed",
                detail: removed.detail, footnote: footnote(removed)
            ) {
                Button("Archive") {
                    Task { await model.archiveSession(session.key, undoManager: undoManager) }
                }
                .buttonStyle(.ds(removed.branch == nil ? .primary : .ghost))
                if removed.branch != nil {
                    Button(isRestoring ? "Restoring…" : "Restore Worktree") {
                        Task { await model.restoreRemovedWorkspace(session.key) }
                    }
                    .buttonStyle(.ds(.primary))
                    .disabled(isRestoring)
                }
            }
            .frame(maxWidth: columnWidth)
            .padding(.horizontal, DS.Space.xxl)
            .padding(.top, DS.Space.md)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
    }

    private func footnote(_ removed: RemovedWorkspace) -> String {
        guard removed.branch != nil else {
            return "Archive it, or check its branch out in a worktree yourself."
        }
        return "Restore Worktree checks the branch out there again. "
            + "Changes that weren't committed went with the folder."
    }
}

#if DEBUG
#Preview("Removed worktree") {
    let app = AppModel.preview()
    let session = SessionModel.preview(in: app, title: "Queue follow-ups while a turn runs")
    let unknown = SessionModel.preview(in: app, title: "Diff view word wrapping")
    if let session, let unknown {
        app.removedWorkspaces[session.key] = RemovedWorkspace(
            branch: "native/queue-follow-ups", detail: "native/queue-follow-ups has 2 commits that aren't merged.")
        app.removedWorkspaces[unknown.key] = RemovedWorkspace(
            branch: nil, detail: "Native can't tell which branch it was on, and it had changes that weren't merged.")
    }
    return DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            if let session, let unknown {
                RemovedWorkspaceNotice(session: session)
                RemovedWorkspaceNotice(session: unknown)
            }
        }
        .frame(width: 760)
    }
    .environment(app)
}
#endif
