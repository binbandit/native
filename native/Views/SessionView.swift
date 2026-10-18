import ACP
import Git
import SwiftUI

struct SessionView: View {
    let session: SessionModel
    /// The subagent whose conversation is open in the inspector.
    @State private var openSubagent: SessionID?
    /// Whether the inspector shows the task's git changes (⌘⇧D) instead of a subagent.
    @State private var showsChanges = false
    @Environment(GitStore.self) private var git
    @Environment(GitHubModel.self) private var gitHub
    @Environment(SettingsPresentation.self) private var settings
    @Environment(AppModel.self) private var model
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth

    var body: some View {
        TranscriptView(session: session) { openSubagent = $0 }
            .environment(\.turnChangesActions, turnChangesActions)
            .environment(\.isPrimaryTranscript, true)
            // A bar rather than an inset, so the transcript gets the system scroll edge effect under it.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    UsageComposerNotices(session: session)
                    ComposerView(session: session)
                }
            }
            // How the task's worktree setup went: the project's setup script running, or why it failed.
            .safeAreaBar(edge: .top, spacing: 0) {
                GitTaskSetupBanner(store: git, folder: session.cwd)
            }
            .terminalPanel(for: session)
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
                // Draws its own outline, like the reference app's header control, rather than sitting on glass.
                ToolbarItem {
                    OpenInButton(location: OpenInLocation(folder: session.cwd, host: projectHost))
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem {
                    GitChangesToolbarButton(model: repository, isPresented: $showsChanges)
                }
                .visibilityPriority(.high)
                ToolbarItem {
                    MCPSessionStatusButton(session: session) { settings.open(.mcpServers) }
                }
            }
            .focusedSceneValue(\.gitChangesInspector, $showsChanges)
            .refreshesGitStatus(of: session, in: git)
            .environment(\.transcriptColumnMaxWidth, columnWidth.maxWidth)
    }

    /// The machine the task's project is on (the selected task's project is the current one).
    private var projectHost: HostID {
        model.currentProject?.host ?? .local
    }

    private var repository: GitRepositoryModel {
        git.model(for: session.cwd)
    }

    /// Review and Commit on the transcript's files-changed card. Commit only shows while there's
    /// something uncommitted.
    private var turnChangesActions: TurnChangesActions {
        let repository = repository
        let gitHub = gitHub
        let canCommit = repository.status.map { !$0.isClean && $0.conflicted.isEmpty } ?? false
        return TurnChangesActions(
            review: { showsChanges = true },
            commitForm: canCommit
                ? { isPresented in
                    AnyView(
                        GitCommitPopover(
                            model: repository, isPresented: isPresented,
                            onCreatePullRequest: {
                                Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                            }))
                } : nil
        )
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
