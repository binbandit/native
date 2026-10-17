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
}
