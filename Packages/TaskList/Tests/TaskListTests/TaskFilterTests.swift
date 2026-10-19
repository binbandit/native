import Foundation
import Testing

@testable import TaskList

@Suite struct TaskFilterTests {
    private let tasks: [TaskFacts] = [
        TaskFacts(activity: .running, agent: "codex", title: "Beta"),
        TaskFacts(activity: .needsYou, agent: "claude-code", title: "alpha"),
        TaskFacts(activity: .done, isUnread: true, agent: "codex", hasUncommittedChanges: true, title: "Gamma"),
        TaskFacts(activity: .failed, agent: "claude-code", hasPullRequest: true, title: "delta"),
        TaskFacts(activity: .idle, agent: "codex", isArchived: true, title: "Archived one"),
    ]

    private func titles(_ filter: TaskFilter) -> [String] {
        filter.apply(to: tasks) { $0 }.map(\.title)
    }

    @Test func noFilterKeepsEverythingButArchived() {
        #expect(titles(TaskFilter()) == ["Beta", "alpha", "Gamma", "delta"])
        #expect(!TaskFilter().isActive)
    }

    @Test func statusesWidenEachOther() {
        #expect(titles(TaskFilter(statuses: [.needsYou, .running])) == ["Beta", "alpha"])
        #expect(titles(TaskFilter(statuses: [.unread])) == ["Gamma"])
        #expect(titles(TaskFilter(statuses: [.done, .failed])) == ["Gamma", "delta"])
    }

    @Test func groupsNarrowEachOther() {
        #expect(titles(TaskFilter(statuses: [.needsYou, .running], agents: ["codex"])) == ["Beta"])
        #expect(titles(TaskFilter(agents: ["codex", "claude-code"])) == ["Beta", "alpha", "Gamma", "delta"])
        #expect(titles(TaskFilter(agents: ["codex"], requiresUncommittedChanges: true)) == ["Gamma"])
        #expect(titles(TaskFilter(requiresUncommittedChanges: true, requiresPullRequest: true)).isEmpty)
        #expect(titles(TaskFilter(requiresPullRequest: true)) == ["delta"])
    }

    @Test func archivedOnlyWhenIncluded() {
        #expect(titles(TaskFilter(includesArchived: true)).contains("Archived one"))
        #expect(titles(TaskFilter(agents: ["codex"], includesArchived: true)) == ["Beta", "Gamma", "Archived one"])
        // Including archived tasks doesn't narrow the list, so it alone doesn't hide projects.
        #expect(!TaskFilter(includesArchived: true).isNarrowing)
        #expect(TaskFilter(includesArchived: true).isActive)
    }

    @Test func sortsByNameLikeTheFinder() {
        let filter = TaskFilter(sort: .name)
        #expect(titles(filter) == ["alpha", "Beta", "delta", "Gamma"])
        let numbered = ["Task 10", "Task 2", "Task 1"].map { TaskFacts(agent: "codex", title: $0) }
        #expect(filter.apply(to: numbered) { $0 }.map(\.title) == ["Task 1", "Task 2", "Task 10"])
    }

    @Test func sortsByUrgencyKeepingTheListOrderForTies() {
        let more = tasks + [TaskFacts(activity: .running, agent: "codex", title: "Epsilon")]
        let sorted = TaskFilter(sort: .status).apply(to: more) { $0 }.map(\.title)
        #expect(sorted == ["alpha", "Beta", "Epsilon", "delta", "Gamma"])
    }

    @Test func recentKeepsTheListOrder() {
        #expect(titles(TaskFilter(sort: .recent)) == ["Beta", "alpha", "Gamma", "delta"])
        #expect(TaskFilter(sort: .name).isActive)
        #expect(!TaskFilter(sort: .name).isNarrowing)
    }

    @Test func chipsListAndRemoveTheActiveFilters() {
        var filter = TaskFilter(
            statuses: [.failed, .needsYou], agents: ["codex", "claude-code"], requiresPullRequest: true,
            includesArchived: true, sort: .name)
        #expect(
            filter.chips == [
                .status(.needsYou), .status(.failed), .agent("claude-code"), .agent("codex"), .pullRequest, .archived,
            ])
        filter.remove(.agent("codex"))
        filter.remove(.status(.needsYou))
        #expect(filter.chips == [.status(.failed), .agent("claude-code"), .pullRequest, .archived])
        filter.clearFilters()
        #expect(filter.chips.isEmpty)
        #expect(filter.sort == .name)
    }

    @Test func togglesAddAndRemove() {
        var filter = TaskFilter()
        filter.toggle(.needsYou)
        filter.toggle(agent: "codex")
        #expect(filter.statuses == [.needsYou] && filter.agents == ["codex"])
        filter.toggle(.needsYou)
        filter.toggle(agent: "codex")
        #expect(!filter.isActive)
    }

    @Test func survivesEncoding() throws {
        let filter = TaskFilter(
            statuses: [.running], agents: ["codex"], requiresUncommittedChanges: true, sort: .status)
        let decoded = try JSONDecoder().decode(TaskFilter.self, from: JSONEncoder().encode(filter))
        #expect(decoded == filter)
    }
}
