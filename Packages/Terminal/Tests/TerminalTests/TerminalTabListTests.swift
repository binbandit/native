import Foundation
import Testing

@testable import Terminal

struct TerminalTabListTests {
    @Test func namesTabsWithTheLowestFreeNumber() {
        var list = TerminalTabList()
        let first = list.add()
        let second = list.add()
        #expect(first.displayTitle == "Terminal")
        #expect(second.displayTitle == "Terminal 2")
        list.close(first.id)
        #expect(list.add().displayTitle == "Terminal")
    }

    @Test func prefersTheTitleTheShellSet() {
        var list = TerminalTabList()
        let tab = list.add()
        list.setTitle("~/native", of: tab.id)
        #expect(list.selected?.displayTitle == "~/native")
        list.setTitle("  ", of: tab.id)
        #expect(list.selected?.displayTitle == "Terminal")
    }

    @Test func numbersTabsThatShowTheSameTitle() {
        var list = TerminalTabList()
        let a = list.add(), b = list.add()
        list.add()
        list.setTitle("~/native", of: a.id)
        list.setTitle("~/native", of: b.id)
        #expect(list.label(of: list.tabs[0]) == "~/native · 1")
        #expect(list.label(of: list.tabs[1]) == "~/native · 2")
        #expect(list.label(of: list.tabs[2]) == "Terminal 3")
        list.setTitle("vim", of: b.id)
        #expect(list.label(of: list.tabs[0]) == "~/native")
    }

    @Test func closingTheSelectedTabSelectsItsNeighbor() {
        var list = TerminalTabList()
        let a = list.add(), b = list.add(), c = list.add()
        list.select(b.id)
        list.close(b.id)
        #expect(list.selectedID == c.id)
        list.close(c.id)
        #expect(list.selectedID == a.id)
        list.close(a.id)
        #expect(list.selectedID == nil)
        #expect(list.isEmpty)
    }

    @Test func closingAnotherTabKeepsTheSelection() {
        var list = TerminalTabList()
        let a = list.add(), b = list.add()
        list.close(a.id)
        #expect(list.selectedID == b.id)
    }

    @Test func cyclesThroughTabsInBothDirections() {
        var list = TerminalTabList()
        let a = list.add(), b = list.add()
        list.selectTab(offset: 1)
        #expect(list.selectedID == a.id)
        list.selectTab(offset: -1)
        #expect(list.selectedID == b.id)
    }

    @Test func aShellThatEndsAtOnceFailedToStart() {
        #expect(TerminalStatus(exitedAfter: .milliseconds(40)) == .failedToStart(.exitedImmediately))
        #expect(TerminalStatus(exitedAfter: .seconds(12)) == .exited)
    }

    @Test func aJobNamesItsTabAndIsFoundByKey() {
        var list = TerminalTabList()
        list.add()
        let tab = list.add(job: TerminalJob(key: "own:1", name: "Test", command: "bun run test"))
        // The job's name wins over whatever title the program sets.
        list.setTitle("vitest", of: tab.id)
        #expect(list.label(of: list.tabs[1]) == "Test")
        #expect(list.tab(forJob: "own:1")?.id == tab.id)
        #expect(list.tab(forJob: "own:2") == nil)
    }

    @Test func aJobEndsWithItsReportedStatusOrAsStopped() {
        let start = Date(timeIntervalSince1970: 0)
        var job = TerminalJob(key: "k", name: "Test", command: "x", startedAt: start)
        job.finish(status: 1, duration: .seconds(3))
        #expect(job.outcome == .exited(status: 1, duration: .seconds(3)))
        // Only the first ending counts: the shell exiting after the command reported is the same run.
        job.finish(status: nil, now: start.addingTimeInterval(9))
        #expect(job.outcome?.duration == .seconds(3))

        var stopped = TerminalJob(key: "k", name: "Dev", command: "x", startedAt: start)
        stopped.isStopping = true
        stopped.finish(status: 130, now: start.addingTimeInterval(5))
        #expect(stopped.outcome == .stopped(duration: .seconds(5)))

        // A program that handles the interrupt and exits cleanly still succeeded.
        var clean = TerminalJob(key: "k", name: "Dev", command: "x", startedAt: start)
        clean.isStopping = true
        clean.finish(status: 0, duration: .seconds(2))
        #expect(clean.outcome?.succeeded == true)
    }
}
