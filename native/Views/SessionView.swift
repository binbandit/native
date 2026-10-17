import ACP
import SwiftUI

struct SessionView: View {
    let session: SessionModel
    /// The subagent whose conversation is open in the inspector.
    @State private var openSubagent: SessionID?
    /// Whether the inspector shows the task's git changes (⌘⇧D) instead of a subagent.
    @State private var showsChanges = false
    @Environment(GitStore.self) private var git
    @Environment(GitHubModel.self) private var gitHub
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth

    var body: some View {
        TranscriptView(session: session) { openSubagent = $0 }
            // A bar rather than an inset, so the transcript gets the system scroll edge effect under it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                ComposerView(session: session)
            }
            // How the task's worktree setup went: the project's setup script running, or why it failed.
            .safeAreaBar(edge: .top, spacing: 0) {
                GitTaskSetupBanner(store: git, folder: session.cwd)
            }
            .focusedSceneValue(\.activeSession, session)
            .navigationTitle(session.displayTitle)
            .navigationSubtitle(
                [session.cwd.abbreviatedPath, repository.summary].compactMap(\.self).joined(separator: " · ")
            )
            // One inspector, showing a subagent or the task's changes; opening one closes the other.
            .inspector(isPresented: isInspectorPresented) {
                if let id = openSubagent, let subagent = session.state.subagents.first(where: { $0.id == id }) {
                    SubagentInspector(subagent: subagent, child: session.child(id))
                        .inspectorColumnWidth(min: 340, ideal: 420, max: 640)
                } else if showsChanges {
                    GitChangesInspector(model: repository) {
                        Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                    }
                    .inspectorColumnWidth(
                        min: GitMetrics.inspectorMinWidth, ideal: GitMetrics.inspectorIdealWidth,
                        max: GitMetrics.inspectorMaxWidth)
                }
            }
            .onChange(of: openSubagent) { _, id in
                if id != nil { showsChanges = false }
            }
            .onChange(of: showsChanges) { _, shows in
                if shows { openSubagent = nil }
            }
            .toolbar {
                ToolbarItem {
                    GitChangesToolbarButton(model: repository, isPresented: $showsChanges)
                }
                .visibilityPriority(.high)
                ToolbarItem {
                    MCPSessionStatusButton(session: session)
                }
            }
            .focusedSceneValue(\.gitChangesInspector, $showsChanges)
            .refreshesGitStatus(of: session, in: git)
            .environment(\.transcriptColumnMaxWidth, columnWidth.maxWidth)
    }

    private var repository: GitRepositoryModel {
        git.model(for: session.cwd)
    }

    private var isInspectorPresented: Binding<Bool> {
        Binding(
            get: { openSubagent != nil || showsChanges },
            set: { isPresented in
                if !isPresented {
                    openSubagent = nil
                    showsChanges = false
                }
            }
        )
    }
}
