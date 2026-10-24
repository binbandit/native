#if DEBUG
import Terminal

enum TerminalToolbarPreviewFixtures {
    static var idle: TerminalActivitySummary {
        var tabs = TerminalTabList()
        tabs.add()
        return tabs.activity
    }

    static var running: TerminalActivitySummary {
        var tabs = TerminalTabList()
        let tab = tabs.add()
        tabs.setCommandRunning(true, of: tab.id)
        return tabs.activity
    }

    static var failed: TerminalActivitySummary {
        var tabs = TerminalTabList()
        let tab = tabs.add()
        tabs.finishCommand(status: 1, in: tab.id)
        return tabs.activity
    }

    static var mixed: TerminalActivitySummary {
        var tabs = TerminalTabList()
        let server = tabs.add()
        let failed = tabs.add()
        tabs.add()
        tabs.setCommandRunning(true, of: server.id)
        tabs.finishCommand(status: 1, in: failed.id)
        return tabs.activity
    }
}
#endif
