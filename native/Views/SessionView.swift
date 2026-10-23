import ACP
import Git
import SwiftUI

struct SessionView: View {
    let session: SessionModel
    /// The subagent whose conversation is open in the inspector.
    @State private var openSubagent: SessionID?
    /// Whether the inspector shows the task's git changes (⌘⇧D) instead of a subagent.
    @State private var showsChanges = false
    /// Which changes the inspector shows; the files-changed card's Review points it at the turn.
    @State private var changesReview = GitChangesReview()
    @Environment(GitStore.self) private var git
    @Environment(GitHubModel.self) private var gitHub
    @Environment(AppModel.self) private var model
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth
    /// Files dropped on the transcript, for the composer to attach.
    @State private var drops = ComposerDropInbox()
    @Environment(\.inspectorRoom) private var inspectorRoom
    @Experiment(.sessionTools) private var usesSessionTools
    private static let subagentInspectorWidth: CGFloat = 420

    var body: some View {
        Group {
            if usesSessionTools {
                SessionToolsScreen(session: session)
            } else {
                standardBody
            }
        }
        .toolbar {
            ToolbarItem { ChangeAgentControl(session: session) }
                .sharedBackgroundVisibility(.hidden)
        }
    }

    private var standardBody: some View {
        TranscriptView(session: session) { id in
            openInspector(Self.subagentInspectorWidth) { openSubagent = id }
        }
        .environment(\.turnChangesActions, turnChangesActions)
        .environment(\.isPrimaryTranscript, true)
        // Native's band under the toolbar, in place of the system's edge effect; inside the bars.
        .dsToolbarBand()
        // A bar rather than an inset, so the transcript gets the system scroll edge effect under it.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // A conversation `/clear` set aside is kept to read: no composer, the way back instead.
                if session.isEarlierConversation {
                    EarlierConversationBar(session: session)
                } else {
                    RemovedWorkspaceNotice(session: session)
                    UsageComposerNotices(session: session)
                    ComposerView(session: session)
                }
            }
        }
        // How the task's worktree setup is going, and any of its scripts that failed (TaskScripts).
        .safeAreaBar(edge: .top, spacing: 0) {
            TaskScriptBanner(folder: session.cwd)
        }
        .composerDropTarget(drops, isEnabled: !session.isEarlierConversation)
        .terminalPanel(for: session)
        .projectActions(for: session)
        .focusedSceneValue(\.activeSession, session)
        .navigationTitle(DSInlineCode.plain(session.displayTitle))
        .navigationSubtitle(
            [session.cwd.abbreviatedPath, repository.summary].compactMap(\.self).joined(separator: " · ")
        )
        // The inspector makes the task its own column, which the window's minimum-size question measures
        // on its own: never at no width (docs/performance.md).
        .platformMinimumContentWidth(DS.Window.detailMinWidth)
        // One inspector, showing a subagent or the task's changes; opening one closes the other.
        .inspector(isPresented: isInspectorPresented) {
            if let id = openSubagent, let subagent = session.state.subagents.first(where: { $0.id == id }) {
                SubagentInspector(subagent: subagent, child: session.child(id))
                    .sessionInspectorColumn(min: 340, ideal: Self.subagentInspectorWidth, max: 640)
            } else if showsChanges {
                GitChangesInspector(model: repository, review: changesReview, session: session) {
                    Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                }
                .sessionInspectorColumn(
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
        .onChange(of: isInspectorPresented.wrappedValue) { _, isPresented in
            if !isPresented { inspectorRoom.release() }
        }
        // Another task or page took the window; the inspector went with this view.
        .onDisappear { inspectorRoom.release() }
        .toolbar {
            // The header controls draw their own outline (`.header` buttons, Open In) rather than
            // sitting on the toolbar's glass, so each hides the shared background. The session's
            // MCP servers live in the composer, beside the context ring.
            ToolbarItem {
                EarlierConversationButton(session: session)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                OpenInButton(location: OpenInLocation(folder: session.cwd, host: projectHost))
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                GitChangesToolbarButton(model: repository, isPresented: showsChangesBinding)
            }
            .sharedBackgroundVisibility(.hidden)
            .visibilityPriority(.high)
        }
        .mcpServersPresentation()
        .focusedSceneValue(\.gitChangesInspector, showsChangesBinding)
        .refreshesGitStatus(of: session, in: git)
        .detectsTurnChanges(of: session, into: changesReview, in: git)
        .environment(\.transcriptColumnMaxWidth, columnWidth.maxWidth)
    }

    /// The machine the task's project is on (the selected task's project is the current one).
    private var projectHost: HostID {
        model.currentProject?.host ?? .local
    }

    private var repository: GitRepositoryModel {
        git.model(for: session.cwd, session: session.key)
    }

    /// Review and Commit on the transcript's files-changed card. Commit only shows while there's
    /// something uncommitted.
    private var turnChangesActions: TurnChangesActions {
        let repository = repository
        let gitHub = gitHub
        let canCommit = repository.canCommit
        return TurnChangesActions(
            review: { reviewTurn(file: nil) },
            commitForm: canCommit
                ? { isPresented in
                    AnyView(
                        GitCommitPopover(
                            model: repository, isPresented: isPresented,
                            onCreatePullRequest: {
                                Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                            }))
                } : nil,
            reviewFile: { reviewTurn(file: $0) },
            latestTurnChanges: changesReview.latestTurnChanges
        )
    }

    /// Opens the changes inspector on the latest turn's changes, and with `file`, that file's.
    private func reviewTurn(file: String?) {
        changesReview.showTurn(of: session, file: file)
        showsChangesBinding.wrappedValue = true
    }

    /// The changes inspector, making room for it before it opens.
    private var showsChangesBinding: Binding<Bool> {
        Binding(
            get: { showsChanges },
            set: { shows in
                if shows {
                    openInspector(GitMetrics.inspectorIdealWidth) { showsChanges = true }
                } else {
                    withTransaction(\.disablesAnimations, true) { showsChanges = false }
                }
            }
        )
    }

    /// Opens an inspector once the window has made room for it, rather than growing; one already
    /// open has its room. The column appears without sliding in: sliding lays the whole window out
    /// again every frame.
    private func openInspector(_ width: CGFloat, _ open: @escaping @MainActor () -> Void) {
        let appear: @MainActor () -> Void = { withTransaction(\.disablesAnimations, true, open) }
        guard !isInspectorPresented.wrappedValue else { return appear() }
        inspectorRoom.open(width, appear)
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

extension View {
    /// The inspector column's widths, with its content never laid out narrower than the minimum.
    /// The window takes its minimum size from the content laid out at no width at all, where wrapped
    /// text (an empty state's message) comes out thousands of points tall, so opening the inspector
    /// grew the window to the height of the screen. Under the toolbar, the column gets the same
    /// band as the page beside it.
    fileprivate func sessionInspectorColumn(min: CGFloat, ideal: CGFloat, max: CGFloat) -> some View {
        frame(minWidth: min).dsToolbarBand().inspectorColumnWidth(min: min, ideal: ideal, max: max)
    }
}
