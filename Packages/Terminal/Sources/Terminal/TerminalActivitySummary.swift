/// The activity of all tabs in a task, including tabs whose panel is hidden.
public struct TerminalActivitySummary: Equatable, Sendable {
    public let openCount: Int
    public let runningCount: Int
    public let failedCount: Int

    public init(tabs: [TerminalTabList.Tab]) {
        openCount = tabs.count
        var running = 0
        var failed = 0
        for tab in tabs {
            if case .failedToStart = tab.status {
                failed += 1
            } else if let job = tab.job {
                if job.isRunning && tab.status == .running {
                    running += 1
                } else if case .exited(let status?, _) = job.outcome, status != 0 {
                    failed += 1
                }
            } else if tab.isCommandRunning && tab.status == .running {
                running += 1
            } else if let status = tab.lastCommandExitStatus, status != 0 {
                failed += 1
            }
        }
        runningCount = running
        failedCount = failed
    }
}
