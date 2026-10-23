import Testing

@testable import Terminal

struct TerminalActivityTests {
    @Test func anOpenShellIsNotAWorkingCommand() {
        var tabs = TerminalTabList()
        #expect(tabs.activity.openCount == 0)
        let tab = tabs.add()
        #expect(tabs.activity.openCount == 1)
        #expect(tabs.activity.runningCount == 0)
        tabs.setTitle("Dev server", of: tab.id)
        #expect(tabs.activity.runningCount == 0)
        tabs.setCommandRunning(true, of: tab.id)
        #expect(tabs.activity.runningCount == 1)
        tabs.finishCommand(status: 0, in: tab.id)
        #expect(tabs.activity.runningCount == 0)
        #expect(tabs.activity.failedCount == 0)
        #expect(tabs.activity.openCount == 1)
    }

    @Test func failureSurvivesAnIdlePromptAndClearsOnTheNextCommand() {
        var tabs = TerminalTabList()
        let tab = tabs.add()
        // A short command can finish between engine activity samples.
        tabs.finishCommand(status: 7, in: tab.id)
        tabs.setCommandRunning(false, of: tab.id)
        #expect(tabs.activity.failedCount == 1)
        tabs.setCommandRunning(true, of: tab.id)
        #expect(tabs.activity.failedCount == 0)
        #expect(tabs.activity.runningCount == 1)
        tabs.finishCommand(status: -1, in: tab.id)
        #expect(tabs.activity.failedCount == 0)
    }

    @Test func summarizesEveryTabWithoutHidingFailureBehindRunningWork() {
        var tabs = TerminalTabList()
        let server = tabs.add()
        let failed = tabs.add()
        tabs.add()
        tabs.setCommandRunning(true, of: server.id)
        tabs.finishCommand(status: 1, in: failed.id)
        #expect(tabs.activity.openCount == 3)
        #expect(tabs.activity.runningCount == 1)
        #expect(tabs.activity.failedCount == 1)
        tabs.close(failed.id)
        #expect(tabs.activity.failedCount == 0)
        tabs.setStatus(.exited, of: server.id)
        tabs.setCommandRunning(true, of: server.id)
        #expect(tabs.activity.runningCount == 0)
    }

    @Test(arguments: [Int32(0), Int32(1)])
    func aBusySampleAfterCompletionStartsTheNextCommandWithoutAnIdleSample(status: Int32) {
        var tabs = TerminalTabList()
        let tab = tabs.add()
        tabs.setCommandRunning(true, of: tab.id)
        tabs.finishCommand(status: status, in: tab.id)
        #expect(tabs.activity.runningCount == 0)
        #expect(tabs.activity.failedCount == (status == 0 ? 0 : 1))

        // The prompt and next command's start can both arrive between activity samples.
        tabs.setCommandRunning(true, of: tab.id)
        #expect(tabs.activity.runningCount == 1)
        #expect(tabs.activity.failedCount == 0)
        #expect(tabs.tabs.first?.lastCommandExitStatus == nil)
        tabs.finishCommand(status: 0, in: tab.id)
        tabs.setCommandRunning(false, of: tab.id)
        #expect(tabs.activity.runningCount == 0)
        #expect(tabs.activity.failedCount == 0)
    }

    @Test func restartingClearsFailureAndClosingIgnoresLateEvents() {
        var tabs = TerminalTabList()
        let tab = tabs.add()
        tabs.finishCommand(status: 1, in: tab.id)
        tabs.resetCommand(in: tab.id)
        #expect(tabs.activity.failedCount == 0)
        tabs.setStatus(.failedToStart(.engineFailed), of: tab.id)
        #expect(tabs.activity.failedCount == 1)
        tabs.close(tab.id)
        tabs.finishCommand(status: 1, in: tab.id)
        tabs.setCommandRunning(true, of: tab.id)
        #expect(tabs.activity.openCount == 0)
        #expect(tabs.activity.failedCount == 0)
    }

    @Test func jobsUseTheirOutcomeAndFailedStartsAreNotRunning() {
        var tabs = TerminalTabList()
        let job = tabs.add(job: TerminalJob(key: "dev", name: "Dev server", command: "serve"))
        #expect(tabs.activity.runningCount == 1)
        tabs.updateJob(of: job.id) { $0.finish(status: 1) }
        #expect(tabs.activity.failedCount == 1)
        #expect(tabs.activity.runningCount == 0)
        tabs.setJob(TerminalJob(key: "dev", name: "Dev server", command: "serve"), of: job.id)
        tabs.updateJob(of: job.id) { $0.finish(status: nil) }
        #expect(tabs.activity.failedCount == 0)
        tabs.setJob(TerminalJob(key: "dev", name: "Dev server", command: "serve"), of: job.id)
        tabs.updateJob(of: job.id) {
            $0.isStopping = true
            $0.finish(status: 130)
        }
        #expect(tabs.activity.failedCount == 0)
        tabs.setJob(TerminalJob(key: "dev", name: "Dev server", command: "serve"), of: job.id)
        tabs.setStatus(.failedToStart(.engineFailed), of: job.id)
        #expect(tabs.activity.failedCount == 1)
        #expect(tabs.activity.runningCount == 0)
    }
}
