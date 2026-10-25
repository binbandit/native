import Testing

@testable import TaskList

struct TaskPairGroupingTests {
    @Test func pairSitsTogetherWhereItsFirstTaskWas() {
        let lists = [["a", "codex", "b", "c", "claude"]]
        let grouped = TaskPairGrouping.grouped(lists, pairs: [["codex", "claude"]])
        #expect(grouped == [["a", "codex", "claude", "b", "c"]])
    }

    @Test func pairKeepsItsOwnOrderWhicheverTaskIsNewer() {
        // The most recent activity sorted Claude Code first; the pair still reads in To-line order.
        let grouped = TaskPairGrouping.grouped([["claude", "a", "codex"]], pairs: [["codex", "claude"]])
        #expect(grouped == [["codex", "claude", "a"]])
    }

    @Test func splitPairsAreLeftAlone() {
        let lists = [["codex", "a"], ["claude", "b"]]
        #expect(TaskPairGrouping.grouped(lists, pairs: [["codex", "claude"]]) == lists)
        let filtered = [["codex", "a"]]
        #expect(TaskPairGrouping.grouped(filtered, pairs: [["codex", "claude"]]) == filtered)
    }
}
