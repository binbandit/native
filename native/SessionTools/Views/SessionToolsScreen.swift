import ACP
import Git
import SessionTools
import SwiftUI

/// The session screen with its tools placed by `SessionToolRegistry` (`docs/session-tools.md`):
/// the conversation and the composer, each tool's fact under the title while it has one, and the
/// open tool's pane in its place. The header has no tool buttons. Behind the Session Tools gate
/// until it replaces `SessionView`'s own screen.
struct SessionToolsScreen: View {
    let session: SessionModel
    var usesTaskWell = false
    @State private var tools = SessionToolsScreenModel()
    @State private var openSubagent: SessionID?
    /// Files dropped on the transcript, for the composer to attach.
    @State private var drops = ComposerDropInbox()
    /// The room the conversation and the side panel share.
    @State private var width: CGFloat = 0
    /// Where the screen starts in the window: the window controls only crowd the title without a sidebar.
    @State private var leadingEdge: CGFloat = 0
    @State private var wellLightTrigger = 0
    @Environment(GitStore.self) private var git
    @Environment(\.inspectorRoom) private var inspectorRoom
    @Environment(\.inspectorSuspension) private var inspectorSuspension
    /// The side tool open when a mode suspended inspectors, which opens again afterwards.
    @State private var reopensSideTool: SessionToolID?
    /// A subagent asked for while inspectors were suspended, which opens once they aren't.
    @State private var reopensSubagent: SessionID?
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth
    @Environment(AppModel.self) private var app

    private var registry: SessionToolRegistry { tools.registry }

    var body: some View {
        let layout = registry.layout(for: session, on: tools)
        let turnChanges = registry.tools.filter { registry.place(of: $0.id) != .off }
            .compactMap { $0.turnChanges?(context($0)) }.first
        ZStack {
            conversation
                .opacity(panelLayout.replacement == nil ? 1 : 0)
                .allowsHitTesting(panelLayout.replacement == nil)
                .accessibilityHidden(panelLayout.replacement != nil)
            if let id = panelLayout.replacement, let tool = registry.tool(id) {
                tool.pane?(context(tool))
                    .environment(\.gitChangesCompact, true)
                    .environment(\.gitChangesClose, GitChangesDismissal { tools.close(id) })
            }
        }
        .environment(\.gitChangesNeutralMarkers, usesTaskWell)
        .environment(\.turnChangesActions, recordActions(turnChanges))
        .environment(\.isPrimaryTranscript, true)
        .dsToolbarBand()
        .safeAreaBar(edge: .bottom, spacing: 0) {
            composer.undoToastBottomInset(isEnabled: !session.isEarlierConversation)
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            TaskScriptBanner(folder: session.cwd)
        }
        .composerDropTarget(drops, isEnabled: !session.isEarlierConversation)
        .terminalPanel(
            for: session, showsToolbarButton: false, isEnabled: usesTaskWell, isWorkbench: usesTaskWell,
            workbenchActions: usesTaskWell ? AnyView(TaskWellWorkbenchActions(session: session)) : nil
        )
        .overlay(alignment: .top) { shade }
        .overlay(alignment: .top) {
            if usesTaskWell { TaskWellLight(trigger: wellLightTrigger) }
        }
        .focusedSceneValue(\.activeSession, session)
        .focusedSceneValue(\.sessionTools, tools)
        .focusedSceneValue(\.gitChangesInspector, toggling(.changes))
        .navigationTitle(DSInlineCode.plain(session.displayTitle))
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if usesTaskWell {
                    TaskWellTitleWiring(session: session, tools: tools)
                        .frame(maxWidth: wellTitleWidth, alignment: .leading)
                } else {
                    SessionToolsTitle(
                        title: session.displayTitle, location: location,
                        facts: layout.facts.compactMap { id in
                            registry.tool(id).flatMap { tool in tool.fact(context(tool)).map { (tool, $0) } }
                        },
                        isOpen: { tools.isOpen($0.id) },
                        action: { tool in
                            if tool.pane == nil { tool.perform(context(tool)) } else { tools.toggle(tool.id) }
                        }
                    )
                }
            }
            .sharedBackgroundVisibility(.hidden)
            if usesTaskWell {
                ToolbarItem(placement: .principal) {
                    TaskWellWiring(
                        session: session, tools: tools, location: location, turnChanges: turnChanges,
                        isCompact: isWellCompact, openSubagents: toggleWellSubagents)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            ToolbarItem {
                EarlierConversationButton(session: session)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        // Measured on its own beside the side panel: never at no width (docs/performance.md).
        .platformMinimumContentWidth(DS.Window.detailMinWidth)
        .inspector(isPresented: isSidePanelDocked) {
            if let id = openSubagent, let target = session.taskWellSubagent(id) {
                SubagentInspector(subagent: target.subagent, child: target.child, showsQuestions: usesTaskWell)
                    .frame(minWidth: DS.SessionTools.sidePanelMinWidth)
                    .dsToolbarBand()
                    .inspectorColumnWidth(
                        min: DS.SessionTools.sidePanelMinWidth, ideal: DS.SessionTools.sidePanelIdealWidth,
                        max: DS.SessionTools.sidePanelMaxWidth)
            } else {
                sidePanel(layout)
            }
        }
        // Outside the side panel, so the room counts the panel's width while it's docked.
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { newWidth in
            // Moving the same review between containers is one layout change. Animating the
            // inspector out while its replacement measures can leave both panes participating.
            withTransaction(\.disablesAnimations, true) { width = newWidth }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minX }) { leadingEdge = $0 }
        .onChange(of: isSidePanelDocked.wrappedValue) { _, isPresented in
            if !isPresented { inspectorRoom.release() }
        }
        .onChange(of: tools.openByPlace[.side]) { _, id in
            if id != nil { openSubagent = nil }
        }
        // Closed and opened the way the user would, so the window makes room the same way.
        .onChange(of: inspectorSuspension != nil) { _, suspends in
            if suspends {
                reopensSideTool = tools.openByPlace[.side]
                reopensSubagent = openSubagent
                openSubagent = nil
                tools.close(.side)
            } else if let id = reopensSubagent {
                reopensSubagent = nil
                reopensSideTool = nil
                openSubagentInspector(id)
            } else if let id = reopensSideTool {
                reopensSideTool = nil
                tools.open(id)
            }
        }
        .onChange(of: session.phase) { previous, current in
            if current == .prompting || (previous == .prompting && current == .idle) {
                wellLightTrigger += 1
            }
        }
        .onChange(of: tools.openTools) { previous, current in
            for id in previous.subtracting(current) {
                if let tool = registry.tool(id) { tool.didClose(context(tool)) }
            }
        }
        .onDisappear {
            tools.close(.side)
            tools.close(.fact)
            tools.makeRoomForSidePanel = { $0() }
            inspectorRoom.release()
        }
        .onAppear { [tools] in
            let availableWidth = $width
            let subagent = $openSubagent
            tools.makeRoomForSidePanel = { [inspectorRoom, weak tools] show in
                guard subagent.wrappedValue == nil else { return show() }
                let layout = SessionToolPanelLayout(
                    open: [:], availableWidth: availableWidth.wrappedValue,
                    minimumConversationWidth: DS.SessionTools.conversationBesidePanelMinWidth,
                    panelWidth: DS.SessionTools.sidePanelIdealWidth)
                guard layout.docksSidePanel else { return show() }
                inspectorRoom.open(DS.SessionTools.sidePanelIdealWidth) {
                    show()
                    // A second click may have cancelled the open while the sidebar was moving.
                    if tools?.openByPlace[.side] == nil, subagent.wrappedValue == nil { inspectorRoom.release() }
                }
            }
        }
        .mcpServersPresentation()
        .refreshesGitStatus(of: session, in: git)
        .detectsTurnChanges(of: session, into: tools.state(for: .changes, GitChangesReview.init), in: git)
        .environment(\.transcriptColumnMaxWidth, columnWidth.maxWidth)
    }

    private var conversation: some View {
        TranscriptView(session: session) { id in openSubagentInspector(id) }
    }

    private func openSubagentInspector(_ id: SessionID) {
        if let inspectorSuspension {
            reopensSubagent = id
            return inspectorSuspension.end()
        }
        let show: @MainActor () -> Void = {
            withTransaction(\.disablesAnimations, true) {
                tools.close(.side)
                openSubagent = id
            }
        }
        if isSidePanelDocked.wrappedValue {
            show()
        } else {
            inspectorRoom.open(DS.SessionTools.sidePanelIdealWidth, show)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            // A conversation `/clear` set aside is kept to read: no composer, the way back instead.
            if session.isEarlierConversation {
                EarlierConversationBar(session: session)
            } else {
                RemovedWorkspaceNotice(session: session)
                UsageComposerNotices(session: session)
                ComposerView(session: session)
                    .environment(\.composerOverlayDismissal, overlayDismissal)
            }
        }
    }

    private var wellTitleWidth: CGFloat {
        let conversationWidth = width - (isSidePanelDocked.wrappedValue ? DS.SessionTools.sidePanelIdealWidth : 0)
        let windowControls = max(0, DS.TaskWell.leadingToolbarWidth - leadingEdge)
        let wellWidth = isWellCompact ? DS.TaskWell.compactWidth : DS.TaskWell.width
        return min(
            DS.TaskWell.titleMaxWidth,
            max(DS.TaskWell.titleMinWidth, (conversationWidth - wellWidth) / 2 - windowControls - DS.Space.lg))
    }

    /// A window too narrow for a docked panel shortens the well before the title gives way.
    private var isWellCompact: Bool { !panelLayout.docksSidePanel }

    private func recordActions(_ actions: TurnChangesActions?) -> TurnChangesActions? {
        guard usesTaskWell, var actions else { return actions }
        actions.isRecordOnly = true
        actions.commitForm = nil
        return actions
    }

    private func toggleWellSubagents(_ requested: SessionID?) {
        if requested == nil, openSubagent != nil {
            openSubagent = nil
        } else if let id = requested ?? session.state.subagents.first?.id {
            openSubagentInspector(id)
        }
    }

    /// A fact's tool, or a side tool while the window is too narrow to dock it, over the
    /// conversation. The fact's wins while both are open.
    @ViewBuilder private var shade: some View {
        let id = panelLayout.overlay
        if let id, let tool = registry.tool(id) {
            GeometryReader { proxy in
                SessionToolsShade(tool: tool, context: context(tool)) { tools.close(id) }
                    .frame(height: proxy.size.height * DS.SessionTools.shadeHeightShare)
                    .padding(.horizontal, DS.Space.lg)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder private func sidePanel(_ layout: SessionToolLayout) -> some View {
        if let id = panelLayout.docked, let open = registry.tool(id) {
            SessionToolsSidePanel(
                tabs: layout.side.compactMap(registry.tool), open: open, context: context,
                select: { tools.open($0) }, close: { tools.close(.side) }
            )
            .frame(minWidth: DS.SessionTools.sidePanelMinWidth)
            .dsToolbarBand()
            // Keep the reserved width exact, including when AppKit restores an older inspector width.
            .inspectorColumnWidth(DS.SessionTools.sidePanelIdealWidth)
        }
    }

    /// Whether a side tool docks beside the conversation: only with room to read both.
    private var panelLayout: SessionToolPanelLayout {
        SessionToolPanelLayout(
            open: tools.openByPlace, availableWidth: width,
            minimumConversationWidth: DS.SessionTools.conversationBesidePanelMinWidth,
            panelWidth: DS.SessionTools.sidePanelIdealWidth,
            replacingConversationWith: usesTaskWell ? .changes : nil)
    }

    private var overlayDismissal: ComposerOverlayDismissal? {
        guard let id = panelLayout.replacement ?? panelLayout.overlay else { return nil }
        return ComposerOverlayDismissal { tools.close(id) }
    }

    private var isSidePanelDocked: Binding<Bool> {
        Binding(
            get: { openSubagent != nil || panelLayout.docked != nil },
            set: { isPresented in
                // SwiftUI acknowledges a layout-driven undock by writing false back. Only a
                // dismissal of a currently docked pane is a request to close the tool.
                if !isPresented, openSubagent != nil || panelLayout.docked != nil {
                    withTransaction(\.disablesAnimations, true) {
                        openSubagent = nil
                        tools.close(.side)
                    }
                }
            }
        )
    }

    /// A tool as a show-or-hide switch, for the commands that toggle it (⇧⌘D for Changes).
    private func toggling(_ id: SessionToolID) -> Binding<Bool>? {
        guard registry.place(of: id) != .off else { return nil }
        return Binding(get: { tools.isOpen(id) }, set: { $0 ? tools.open(id) : tools.close(id) })
    }

    private func context(_ tool: SessionToolContribution) -> SessionToolContext {
        SessionToolContext(session: session, screen: tools, tool: tool.id)
    }

    /// The task's branch, else its folder, at the head of the facts.
    private var location: String {
        guard case .branch(let name)? = git.model(for: session.cwd, session: session.key).branch?.head else {
            return usesTaskWell ? app.projectName(of: session) : session.cwd.abbreviatedPath
        }
        return usesTaskWell ? "\(app.projectName(of: session)) · \(name)" : name
    }
}

#if DEBUG
// Preview the screen's chrome with fixed data; the live screen starts repository watchers.
#Preview("Session tools - Facts and docked Changes") {
    DSPreviewPair {
        VStack(alignment: .leading) {
            SessionToolsPreviewFixtures.title()
            HStack {
                EmptyStateView(
                    "Conversation", systemImage: "text.bubble",
                    message: "The task and composer stay beside Changes."
                )
                .frame(width: DS.SessionTools.conversationBesidePanelMinWidth)
                SessionToolsPreviewFixtures.sidePanel
            }
        }
    }
}
#endif

#if DEBUG
#Preview("Well - Narrow Changes with composer") {
    DSPreviewPair {
        VStack(spacing: 0) {
            GitChangesInspector(model: GitPreviewFixtures.model, review: GitChangesReview())
                .environment(\.gitChangesCompact, true)
                .environment(\.gitChangesNeutralMarkers, true)
                .environment(\.gitChangesClose, GitChangesDismissal {})
            ComposerStatePreviewFixtures.finePrint(phase: .idle, draft: "Why fixedSize here?")
        }
        .frame(width: DS.ComposerSettings.width, height: DS.TaskWell.panelWidth)
    }
}
#endif
