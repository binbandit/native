#if DEBUG
import ACP
import Git
import ProjectActions
import SwiftUI
import Terminal

/// The session screen with its tools placed by a `SessionChromeDirection`: the conversation and
/// composer as today, and each tool the user has on in its one place (the header's facts, the side
/// panel, the workbench). The header carries no tool buttons. A prototype for choosing a direction;
/// `SessionView` shows it only for `-sessionChrome`.
struct SessionChromeScreen: View {
    let session: SessionModel

    @State private var chrome: SessionChromeModel
    @State private var changesReview = GitChangesReview()
    @State private var drops = ComposerDropInbox()
    @State private var availableHeight: CGFloat = 0
    @Environment(GitStore.self) private var git
    @Environment(GitHubModel.self) private var gitHub
    @Environment(AppModel.self) private var model
    @Environment(TerminalStore.self) private var terminals
    @Environment(ProjectActionRunner.self) private var runner
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dsAccentPalette) private var palette
    @Environment(\.dsLightTone) private var lightTone
    @Environment(\.dsDarkTone) private var darkTone
    @Environment(\.dsTransparency) private var transparency
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(session: SessionModel, direction: SessionChromeDirection) {
        self.session = session
        _chrome = State(initialValue: SessionChromeModel(direction: direction))
    }

    var body: some View {
        let context = context
        let usesFacts = !chrome.arrangement.tools(in: .header).isEmpty
        VStack(spacing: 0) {
            conversation
                .overlay(alignment: .top) { shade(context) }
            if !chrome.arrangement.tools(in: .bottom).isEmpty {
                SessionChromeWorkbench(
                    context: context, chrome: chrome,
                    maxHeight: availableHeight - SessionChromeMetrics.conversationMinHeight)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { availableHeight = $0 }
        .focusedSceneValue(\.activeSession, session)
        .navigationTitle(DSInlineCode.plain(session.displayTitle))
        .navigationSubtitle(usesFacts ? "" : subtitle)
        .toolbar(removing: usesFacts ? .title : nil)
        .platformMinimumContentWidth(DS.Window.detailMinWidth)
        .inspector(isPresented: isSidePresented) {
            SessionChromeSidePanel(context: context, chrome: chrome)
                .frame(minWidth: SessionChromeMetrics.sidePanelMinWidth)
                .dsToolbarBand()
                .inspectorColumnWidth(
                    min: SessionChromeMetrics.sidePanelMinWidth, ideal: SessionChromeMetrics.sidePanelIdealWidth,
                    max: SessionChromeMetrics.sidePanelMaxWidth)
        }
        .toolbar { toolbar(context, usesFacts: usesFacts) }
        .overlay {
            if chrome.isArranging {
                // Where the command palette floats; a click outside closes it.
                ZStack {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { chrome.isArranging = false }
                        .accessibilityHidden(true)
                    SessionChromeToolsEditor(chrome: chrome)
                }
                .transition(.opacity.animation(.dsPopover))
            }
        }
        .mcpServersPresentation()
        .focusedSceneValue(\.gitChangesInspector, showsChanges)
        .refreshesGitStatus(of: session, in: git)
        // The project's actions are read when a task shows, as the Run menu does, so Run's fact and
        // pane know them.
        .task(id: session.cwd) {
            if let target = ProjectActionsWiring.target(for: session, model: model) {
                runner.store.refresh(target.project)
            }
        }
        .environment(\.transcriptColumnMaxWidth, columnWidth.maxWidth)
        .onChange(of: terminal.isVisible, initial: true) { _, isVisible in
            // ⌃`, View ▸ Show Terminal and a run's Show all set the panel's visibility.
            if isVisible, !chrome.isShowing(.terminal) {
                chrome.show(.terminal)
                if !chrome.isShowing(.terminal) { terminal.isVisible = false }
            } else if !isVisible, chrome.isShowing(.terminal) {
                chrome.hide(.terminal)
            }
        }
        .onChange(of: chrome.isShowing(.terminal)) { _, isShowing in
            if isShowing, !terminal.isVisible {
                terminal.show()
            } else if !isShowing, terminal.isVisible {
                terminal.isVisible = false
            }
        }
        .onChange(of: appearanceKey, initial: true) { _, key in
            let appearance = TerminalAppearance(key.colorScheme)
            terminals.setAppearance(
                appearance,
                chrome: .designSystem(
                    appearance: appearance, palette: key.palette, lightTone: key.lightTone, darkTone: key.darkTone),
                transparency: key.transparency)
        }
    }

    /// The transcript and the composer, as the session screen has them.
    private var conversation: some View {
        TranscriptView(session: session) { id in
            chrome.openSubagent = id
            chrome.show(.agents)
        }
        .environment(\.turnChangesActions, turnChangesActions)
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
    }

    @ViewBuilder private func shade(_ context: SessionChromeContext) -> some View {
        if let tool = chrome.tool(in: .header) {
            SessionChromeShade(tool: tool, context: context, chrome: chrome)
                .frame(height: max(availableHeight * SessionChromeMetrics.shadeHeightShare, 0))
                .padding(.horizontal, DS.Space.lg)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ context: SessionChromeContext, usesFacts: Bool) -> some ToolbarContent {
        if usesFacts {
            ToolbarItem(placement: .navigation) {
                SessionChromeTitle(
                    title: session.displayTitle, subtitle: subtitle, context: context, chrome: chrome)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarItem {
            EarlierConversationButton(session: session)
        }
        .sharedBackgroundVisibility(.hidden)
        if !chrome.arrangement.tools(in: .side).isEmpty {
            ToolbarItem(placement: .primaryAction) {
                let isOpen = chrome.tool(in: .side) != nil
                WindowToolbarButton(
                    isOpen ? "Hide Side Panel" : "Show Side Panel", systemImage: "sidebar.right", isActive: isOpen
                ) {
                    if isOpen {
                        chrome.close(.side)
                    } else {
                        chrome.reopen(.side, preferring: sideLiveTools(context))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // Something new waits in the closed panel.
                    if !isOpen, !sideLiveTools(context).isEmpty {
                        StatusDot()
                    }
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func sideLiveTools(_ context: SessionChromeContext) -> [SessionChromeTool] {
        chrome.arrangement.tools(in: .side).filter { $0.hasPane && context.fact(for: $0).isLive }
    }

    private var context: SessionChromeContext {
        SessionChromeContext(
            session: session, repository: repository, terminals: terminals, runner: runner,
            target: ProjectActionsWiring.target(for: session, model: model),
            openIn: OpenInLocation(folder: session.cwd, host: model.currentProject?.host ?? .local), gitHub: gitHub,
            changesReview: changesReview)
    }

    private var repository: GitRepositoryModel {
        git.model(for: session.cwd)
    }

    private var terminal: TerminalPanelModel {
        terminals.panel(for: session)
    }

    private var subtitle: String {
        [session.cwd.abbreviatedPath, repository.summary].compactMap(\.self).joined(separator: " · ")
    }

    private var isSidePresented: Binding<Bool> {
        Binding(
            get: { chrome.tool(in: .side) != nil },
            set: { if !$0 { chrome.close(.side) } }
        )
    }

    /// ⇧⌘D and the turn card's Review open Changes wherever it lives.
    private var showsChanges: Binding<Bool> {
        Binding(
            get: { chrome.isShowing(.changes) },
            set: { shows in
                if shows {
                    chrome.show(.changes)
                } else {
                    chrome.hide(.changes)
                    changesReview.reset()
                }
            }
        )
    }

    private var turnChangesActions: TurnChangesActions {
        let repository = repository
        let gitHub = gitHub
        return TurnChangesActions(
            review: { reviewTurn(file: nil) },
            commitForm: repository.canCommit
                ? { isPresented in
                    AnyView(
                        GitCommitPopover(
                            model: repository, isPresented: isPresented,
                            onCreatePullRequest: {
                                Task { await GitHubGitWiring.createPullRequest(from: repository, gitHub: gitHub) }
                            }))
                } : nil,
            reviewFile: { reviewTurn(file: $0) }
        )
    }

    private func reviewTurn(file: String?) {
        changesReview.showTurn(of: session, file: file)
        chrome.show(.changes)
    }

    private var appearanceKey: TerminalAppearanceKey {
        TerminalAppearanceKey(
            colorScheme: colorScheme, palette: palette, lightTone: lightTone, darkTone: darkTone,
            transparency: TerminalTransparency(
                transparency, reduceTransparency: reduceTransparency,
                isTrueBlack: colorScheme == .dark && darkTone == .trueBlack))
    }
}
#endif
