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
    @State private var wellLightTrigger = 0
    @Environment(GitStore.self) private var git
    @Environment(\.inspectorRoom) private var inspectorRoom
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth

    private var registry: SessionToolRegistry { tools.registry }

    var body: some View {
        let layout = registry.layout(for: session, on: tools)
        let turnChanges = registry.tools.filter { registry.place(of: $0.id) != .off }
            .compactMap { $0.turnChanges?(context($0)) }.first
        TranscriptView(session: session) { id in
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
        .environment(\.turnChangesActions, recordActions(turnChanges))
        .environment(\.isPrimaryTranscript, true)
        .dsToolbarBand()
        .safeAreaBar(edge: .bottom, spacing: 0) { composer }
        .safeAreaBar(edge: .top, spacing: 0) {
            TaskScriptBanner(folder: session.cwd)
        }
        .composerDropTarget(drops, isEnabled: !session.isEarlierConversation)
        .terminalPanel(for: session, showsToolbarButton: false, isEnabled: usesTaskWell)
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
                SessionToolsTitle(
                    title: session.displayTitle, location: location,
                    facts: usesTaskWell
                        ? []
                        : layout.facts.compactMap { id in
                            registry.tool(id).flatMap { tool in tool.fact(context(tool)).map { (tool, $0) } }
                        },
                    isOpen: { tools.isOpen($0.id) },
                    action: { tool in
                        if tool.pane == nil { tool.perform(context(tool)) } else { tools.toggle(tool.id) }
                    }
                )
                .frame(maxWidth: usesTaskWell ? wellTitleWidth : nil, alignment: .leading)
            }
            .sharedBackgroundVisibility(.hidden)
            if usesTaskWell {
                ToolbarItem(placement: .principal) {
                    TaskWellWiring(
                        session: session, tools: tools, location: location, turnChanges: turnChanges,
                        openSubagents: toggleWellSubagents)
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
            if let id = openSubagent, let subagent = session.state.subagents.first(where: { $0.id == id }) {
                SubagentInspector(subagent: subagent, child: session.child(id))
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
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onChange(of: isSidePanelDocked.wrappedValue) { _, isPresented in
            if !isPresented { inspectorRoom.release() }
        }
        .onChange(of: tools.openByPlace[.side]) { _, id in
            if id != nil { openSubagent = nil }
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
        min(
            DS.TaskWell.titleMaxWidth,
            max(DS.TaskWell.titleMinWidth, (width - DS.TaskWell.width) / 2 - DS.TaskWell.leadingToolbarWidth))
    }

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
            tools.close(.side)
            inspectorRoom.open(DS.SessionTools.sidePanelIdealWidth) { openSubagent = id }
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
        if let id = tools.openByPlace[.side], let open = registry.tool(id) {
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
            panelWidth: DS.SessionTools.sidePanelIdealWidth)
    }

    private var overlayDismissal: ComposerOverlayDismissal? {
        guard let id = panelLayout.overlay else { return nil }
        return ComposerOverlayDismissal { tools.close(id) }
    }

    private var isSidePanelDocked: Binding<Bool> {
        Binding(
            get: { openSubagent != nil || panelLayout.docked != nil },
            set: { isPresented in
                if !isPresented {
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
            return usesTaskWell ? session.cwd.lastPathComponent : session.cwd.abbreviatedPath
        }
        return usesTaskWell ? "\(session.cwd.lastPathComponent) · \(name)" : name
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
