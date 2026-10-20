import ACP
import Git
import SessionTools
import SwiftUI

/// A task's screen: the conversation and the composer, and its tools placed by
/// `SessionToolRegistry` (`docs/session-tools.md`): each tool's fact under the title while it has
/// one, and the open tool's pane in its place. The header has no tool buttons.
struct SessionView: View {
    let session: SessionModel
    @State private var tools = SessionToolsScreenModel()
    /// Files dropped on the transcript, for the composer to attach.
    @State private var drops = ComposerDropInbox()
    /// The room the conversation, the side panel and the workbench share.
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0
    @Environment(GitStore.self) private var git
    @Environment(\.inspectorRoom) private var inspectorRoom
    @Experiment(.transcriptWidth) private var columnWidth: TranscriptWidth

    private var registry: SessionToolRegistry { tools.registry }

    var body: some View {
        let layout = registry.layout(for: session, on: tools)
        let transcript = SessionTranscriptActions.merging(
            registry.tools.filter { registry.place(of: $0.id) != .off }.compactMap { $0.transcript?(context($0)) })
        VStack(spacing: 0) {
            TranscriptView(session: session) { id in transcript.openSubagent?(id) }
                .environment(\.turnChangesActions, transcript.turnChanges)
                .environment(\.isPrimaryTranscript, true)
                .dsToolbarBand()
                .safeAreaBar(edge: .bottom, spacing: 0) { composer }
                .safeAreaBar(edge: .top, spacing: 0) {
                    TaskScriptBanner(folder: session.cwd)
                }
                .composerDropTarget(drops, isEnabled: !session.isEarlierConversation)
                .overlay(alignment: .top) { shade }
            if !layout.workbench.isEmpty {
                SessionToolsWorkbench(
                    tabs: layout.workbench.compactMap(registry.tool),
                    open: tools.openByPlace[.workbench].flatMap(registry.tool), context: context,
                    select: { tools.open($0) }, close: { tools.close(.workbench) },
                    maxHeight: height - SessionToolMetrics.conversationAboveWorkbenchMinHeight)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        .background {
            // Each tool's own bookkeeping while it's on: the terminal's colors and ⌃`.
            ForEach(registry.tools.filter { registry.place(of: $0.id) != .off }) { tool in
                tool.companion?(context(tool))
            }
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
                    facts: layout.facts.compactMap { id in
                        registry.tool(id).flatMap { tool in tool.fact(context(tool)).map { (tool, $0) } }
                    },
                    isOpen: { tools.isOpen($0.id) },
                    menu: { tool in tool.menu?(context(tool)) },
                    action: { tool in
                        if tool.pane == nil { tool.perform(context(tool)) } else { tools.toggle(tool.id) }
                    })
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                EarlierConversationButton(session: session)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        // Measured on its own beside the side panel: never at no width (docs/performance.md).
        .platformMinimumContentWidth(DS.Window.detailMinWidth)
        .inspector(isPresented: isSidePanelDocked) { sidePanel(layout) }
        // Outside the side panel, so the room counts the panel's width while it's docked.
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onChange(of: tools.openByPlace[.side] == nil) { _, isClosed in
            if isClosed { inspectorRoom.release() }
        }
        .onDisappear { inspectorRoom.release() }
        .onAppear {
            tools.makeRoomForSidePanel = { [inspectorRoom] show in
                guard docksSidePanel else { return show() }
                inspectorRoom.open(SessionToolMetrics.sidePanelIdealWidth, show)
            }
        }
        // View ▸ Toggle Subagent Inspector (⌥⌘I) asks the task; the Subagents tool answers.
        .onChange(of: session.isSubagentInspectorToggleRequested) { _, isRequested in
            guard isRequested else { return }
            session.isSubagentInspectorToggleRequested = false
            tools.toggle(.subagents)
        }
        .mcpServersPresentation()
        .refreshesGitStatus(of: session, in: git)
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
            }
        }
    }

    /// A fact's tool, or a side tool while the window is too narrow to dock it, over the
    /// conversation. The fact's wins while both are open.
    @ViewBuilder private var shade: some View {
        let id = tools.openByPlace[.fact] ?? (docksSidePanel ? nil : tools.openByPlace[.side])
        if let id, let tool = registry.tool(id) {
            GeometryReader { proxy in
                SessionToolsShade(tool: tool, context: context(tool)) { tools.close(id) }
                    .frame(height: proxy.size.height * SessionToolMetrics.shadeHeightShare)
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
            .frame(minWidth: SessionToolMetrics.sidePanelMinWidth)
            .dsToolbarBand()
            .inspectorColumnWidth(
                min: SessionToolMetrics.sidePanelMinWidth, ideal: SessionToolMetrics.sidePanelIdealWidth,
                max: SessionToolMetrics.sidePanelMaxWidth)
        }
    }

    /// Whether a side tool docks beside the conversation: only with room to read both.
    private var docksSidePanel: Bool {
        width >= SessionToolMetrics.conversationBesidePanelMinWidth + SessionToolMetrics.sidePanelIdealWidth
    }

    private var isSidePanelDocked: Binding<Bool> {
        Binding(
            get: { docksSidePanel && tools.openByPlace[.side] != nil },
            set: { if !$0 { tools.close(.side) } }
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
        guard case .branch(let name)? = git.model(for: session.cwd).branch?.head else {
            return session.cwd.abbreviatedPath
        }
        return name
    }
}
