#if DEBUG
import SwiftUI

/// The panel beside the conversation (direction A, and D's side place): one tab per tool that
/// has something to show, the selected tool's pane under them. Tools with nothing to show wait in
/// the "…" menu, so the strip only ever lists what matters now.
struct SessionChromeSidePanel: View {
    let context: SessionChromeContext
    let chrome: SessionChromeModel

    var body: some View {
        let tools = chrome.arrangement.tools(in: .side)
        let selected = chrome.tool(in: .side)
        let tabs = tools.filter { tool in
            tool.hasPane && (tool == selected || tool == .terminal || context.fact(for: tool).isLive)
        }
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.xxs) {
                ForEach(tabs) { tool in
                    SessionChromeTab(
                        title: context.tabTitle(for: tool), systemImage: tool.systemImage,
                        fact: tool == .terminal ? nil : context.fact(for: tool),
                        isSelected: tool == selected, help: tool.help
                    ) {
                        chrome.show(tool)
                    }
                }
                Spacer(minLength: DS.Space.sm)
                if tools.contains(.openIn) {
                    SessionChromeOpenInControl(location: context.openIn)
                }
                SessionChromeMoreMenu(tools: tools.filter { $0.hasPane && !tabs.contains($0) }, chrome: chrome)
            }
            .padding(.horizontal, DS.Space.md)
            .frame(height: SessionChromeMetrics.stripHeight)
            SeparatorLine()
            if let selected {
                SessionChromeToolPane(tool: selected, context: context, chrome: chrome)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.dsBackground)
    }
}
#endif
