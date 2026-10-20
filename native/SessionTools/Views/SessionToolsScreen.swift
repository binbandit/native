import ACP
import Git
import SwiftUI

/// The session screen with its tools placed by `SessionToolRegistry` (`docs/session-tools.md`):
/// the conversation and the composer, and each tool that's on in its one place. The header has no
/// tool buttons. Behind the Session Tools gate until it replaces `SessionView`'s own screen.
struct SessionToolsScreen: View {
    let session: SessionModel
    /// The subagent whose conversation is open beside the task's.
    @State private var openSubagent: SessionID?
    /// Files dropped on the transcript, for the composer to attach.
    @State private var drops = ComposerDropInbox()
    @Environment(GitStore.self) private var git
    @Environment(\.inspectorRoom) private var inspectorRoom
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth

    var body: some View {
        TranscriptView(session: session) { id in
            openSidePanel { openSubagent = id }
        }
        .environment(\.isPrimaryTranscript, true)
        .dsToolbarBand()
        .safeAreaBar(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if session.isEarlierConversation {
                    EarlierConversationBar(session: session)
                } else {
                    RemovedWorkspaceNotice(session: session)
                    UsageComposerNotices(session: session)
                    ComposerView(session: session)
                }
            }
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            TaskScriptBanner(folder: session.cwd)
        }
        .composerDropTarget(drops, isEnabled: !session.isEarlierConversation)
        .focusedSceneValue(\.activeSession, session)
        .navigationTitle(DSInlineCode.plain(session.displayTitle))
        .navigationSubtitle(
            [session.cwd.abbreviatedPath, git.model(for: session.cwd).summary].compactMap(\.self)
                .joined(separator: " · ")
        )
        // Measured on its own beside the side panel: never at no width (docs/performance.md).
        .platformMinimumContentWidth(DS.Window.detailMinWidth)
        .inspector(isPresented: isSidePanelPresented) {
            if let id = openSubagent, let subagent = session.state.subagents.first(where: { $0.id == id }) {
                SubagentInspector(subagent: subagent, child: session.child(id))
                    .frame(minWidth: SessionToolMetrics.sidePanelMinWidth)
                    .dsToolbarBand()
                    .inspectorColumnWidth(
                        min: SessionToolMetrics.sidePanelMinWidth, ideal: SessionToolMetrics.sidePanelIdealWidth,
                        max: SessionToolMetrics.sidePanelMaxWidth)
            }
        }
        .onChange(of: isSidePanelPresented.wrappedValue) { _, isPresented in
            if !isPresented { inspectorRoom.release() }
        }
        .onDisappear { inspectorRoom.release() }
        .toolbar {
            ToolbarItem {
                EarlierConversationButton(session: session)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .mcpServersPresentation()
        .refreshesGitStatus(of: session, in: git)
        .environment(\.transcriptColumnMaxWidth, columnWidth.maxWidth)
    }

    /// Opens the side panel once the window has made room for it, without sliding it in: sliding
    /// lays the whole window out again every frame.
    private func openSidePanel(_ open: @escaping @MainActor () -> Void) {
        let appear: @MainActor () -> Void = { withTransaction(\.disablesAnimations, true, open) }
        guard !isSidePanelPresented.wrappedValue else { return appear() }
        inspectorRoom.open(SessionToolMetrics.sidePanelIdealWidth, appear)
    }

    /// Closes without animation too: closing it animated, while the window settles its columns, sent
    /// AppKit into a constraint loop.
    private var isSidePanelPresented: Binding<Bool> {
        Binding(
            get: { openSubagent != nil },
            set: { isPresented in
                if !isPresented { withTransaction(\.disablesAnimations, true) { openSubagent = nil } }
            }
        )
    }
}
