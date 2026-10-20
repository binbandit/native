#if DEBUG
import SwiftUI
import Terminal

/// The workbench under the conversation (direction B, and D's bottom place). Its strip is the
/// handle: every terminal and every run is a tab of its own, beside the tools that have something
/// to show. Closed, only the strip shows, and only while something in it is live.
struct SessionChromeWorkbench: View {
    let context: SessionChromeContext
    let chrome: SessionChromeModel
    /// The most the pane may take, so the conversation and composer keep their room.
    let maxHeight: CGFloat

    @State private var height = SessionChromeMetrics.workbenchHeight
    @State private var dragStart: CGFloat?

    var body: some View {
        let tools = chrome.arrangement.tools(in: .bottom)
        let selected = chrome.tool(in: .bottom)
        let terminalTabs = tools.contains(.terminal) ? context.terminal.tabs.tabs : []
        // Runs already have tabs of their own while the terminal is here, so Run waits in "…".
        let toolTabs = tools.filter { tool in
            guard tool.hasPane, tool != .terminal else { return false }
            if tool == selected { return true }
            return context.fact(for: tool).isLive && !(tool == .run && tools.contains(.terminal))
        }
        if selected != nil || !terminalTabs.isEmpty || !toolTabs.isEmpty {
            VStack(spacing: 0) {
                if selected != nil {
                    resizeEdge
                } else {
                    SeparatorLine()
                }
                strip(tools: tools, terminalTabs: terminalTabs, toolTabs: toolTabs, selected: selected)
                if let selected {
                    SeparatorLine()
                    SessionChromeToolPane(tool: selected, context: context, chrome: chrome, showsTerminalTabs: false)
                        .frame(
                            height: min(
                                max(height, SessionChromeMetrics.workbenchMinHeight),
                                max(maxHeight, SessionChromeMetrics.workbenchMinHeight)))
                }
            }
            .background(.dsBackground)
        }
    }

    private func strip(
        tools: [SessionChromeTool], terminalTabs: [TerminalTabList.Tab], toolTabs: [SessionChromeTool],
        selected: SessionChromeTool?
    ) -> some View {
        let panel = context.terminal
        return HStack(spacing: DS.Space.xxs) {
            ForEach(terminalTabs) { tab in
                SessionChromeTab(
                    title: panel.tabs.label(of: tab), systemImage: tab.job == nil ? "apple.terminal" : "play",
                    fact: tab.job.map(Self.fact), isSelected: selected == .terminal && panel.tabs.selectedID == tab.id
                ) {
                    panel.select(tab.id)
                    chrome.show(.terminal)
                }
            }
            if tools.contains(.terminal), terminalTabs.isEmpty {
                SessionChromeTab(
                    title: SessionChromeTool.terminal.title, systemImage: SessionChromeTool.terminal.systemImage,
                    isSelected: false, help: SessionChromeTool.terminal.help
                ) {
                    chrome.show(.terminal)
                }
            } else if tools.contains(.terminal) {
                IconButton("New Terminal Tab", systemImage: "plus") {
                    panel.newTab()
                    chrome.show(.terminal)
                }
            }
            if !terminalTabs.isEmpty, !toolTabs.isEmpty {
                SeparatorLine(axis: .vertical)
                    .frame(height: DS.Space.lg)
                    .padding(.horizontal, DS.Space.sm)
            }
            ForEach(toolTabs) { tool in
                SessionChromeTab(
                    title: context.tabTitle(for: tool), systemImage: tool.systemImage, fact: context.fact(for: tool),
                    isSelected: tool == selected, help: tool.help
                ) {
                    chrome.show(tool)
                }
            }
            Spacer(minLength: DS.Space.md)
            if selected == .terminal, let tab = panel.tabs.selected, let job = tab.job, job.isRunning {
                TerminalJobControls(job: job) { panel.stopJob(in: tab.id) }
            }
            if tools.contains(.openIn) {
                SessionChromeOpenInControl(location: context.openIn)
            }
            SessionChromeMoreMenu(
                tools: tools.filter { $0.hasPane && $0 != .terminal && !toolTabs.contains($0) }, chrome: chrome)
            IconButton(
                selected == nil ? "Show Workbench" : "Hide Workbench",
                systemImage: selected == nil ? "chevron.up" : "chevron.down"
            ) {
                if selected == nil {
                    chrome.reopen(.bottom, preferring: terminalTabs.isEmpty ? toolTabs : [.terminal])
                } else {
                    chrome.close(.bottom)
                }
            }
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: SessionChromeMetrics.stripHeight)
    }

    /// A run's tab says how it's going, like the run's own fact.
    private static func fact(_ job: TerminalJob) -> SessionChromeFact {
        let failed = job.outcome.map { ProjectActionRunState.finished($0).hasFailed } ?? false
        return SessionChromeFact(
            text: job.name, tone: job.isRunning ? .running : failed ? .failed : .quiet, isLive: true)
    }

    /// The strip's top edge, dragged to resize the pane.
    private var resizeEdge: some View {
        SeparatorLine()
            .overlay {
                Color.clear
                    .frame(height: DS.Space.md)
                    .contentShape(.rect)
                    #if os(macOS)
                .pointerStyle(.rowResize)
                    #endif
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStart ?? height
                                dragStart = start
                                height = min(
                                    max(start - value.translation.height, SessionChromeMetrics.workbenchMinHeight),
                                    maxHeight)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
    }
}
#endif
