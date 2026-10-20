#if DEBUG
import ACP
import Foundation
import Observation

/// One session screen's chrome: where its tools live, and which tool each place shows.
@Observable
final class SessionChromeModel {
    let direction: SessionChromeDirection
    private(set) var arrangement: SessionChromeArrangement
    /// The tool each place shows; a place without one is closed.
    private(set) var shown: [SessionChromePlace: SessionChromeTool] = [:]
    /// The tool each place showed last, for reopening it.
    private var last: [SessionChromePlace: SessionChromeTool] = [:]
    /// The tools editor, over the session.
    var isArranging = UserDefaults.standard.bool(forKey: "sessionChromeArranging")
    /// The subagent whose conversation the Subagents tool shows.
    var openSubagent: SessionID?

    init(direction: SessionChromeDirection) {
        self.direction = direction
        arrangement = direction.initialArrangement
    }

    func tool(in place: SessionChromePlace) -> SessionChromeTool? {
        shown[place]
    }

    func isShowing(_ tool: SessionChromeTool) -> Bool {
        arrangement.place(of: tool).map { shown[$0] == tool } ?? false
    }

    func show(_ tool: SessionChromeTool) {
        guard tool.hasPane, let place = arrangement.place(of: tool) else { return }
        shown[place] = tool
        last[place] = tool
    }

    func hide(_ tool: SessionChromeTool) {
        for (place, shownTool) in shown where shownTool == tool {
            shown[place] = nil
        }
    }

    func toggle(_ tool: SessionChromeTool) {
        if isShowing(tool) { hide(tool) } else { show(tool) }
    }

    func close(_ place: SessionChromePlace) {
        shown[place] = nil
    }

    /// Opens a place on the tool it showed last, else the first of `preferred` it holds.
    func reopen(_ place: SessionChromePlace, preferring preferred: [SessionChromeTool]) {
        let tools = arrangement.tools(in: place).filter(\.hasPane)
        guard let tool = last[place].flatMap({ tools.contains($0) ? $0 : nil }) ?? preferred.first ?? tools.first
        else { return }
        show(tool)
    }

    func move(_ tool: SessionChromeTool, to place: SessionChromePlace?) {
        hide(tool)
        arrangement.move(tool, to: place)
    }

    func reset() {
        shown = [:]
        arrangement = direction.initialArrangement
    }
}
#endif
