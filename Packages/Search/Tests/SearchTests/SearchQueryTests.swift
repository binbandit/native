import Foundation
import Testing

@testable import Search

struct SearchQueryTests {
    @Test func symbolsBecomePhrasesAndTheLastWordIsAPrefix() {
        let parsed = ParsedSearchQuery(SearchQuery("AppModel.swift git rebase -i login tim"))
        #expect(parsed.expression == #""appmodel swift" "git" "rebase" "i" "login" "tim"*"#)
    }

    @Test func aFinishedWordIsntAPrefix() {
        #expect(ParsedSearchQuery(SearchQuery("timeout ")).expression == #""timeout""#)
        #expect(ParsedSearchQuery(SearchQuery("\"login timeout\"")).expression == #""login timeout""#)
        // One or two letters would match most of the index.
        #expect(ParsedSearchQuery(SearchQuery("fix a")).expression == #""fix" "a""#)
        #expect(ParsedSearchQuery(SearchQuery("fix th")).expression == #""fix" "th""#)
    }

    @Test func operatorsBecomeFilters() throws {
        let parsed = ParsedSearchQuery(
            SearchQuery("agent:codex project:native role:user has:diff is:archived after:2026-01-31 crash"))
        #expect(parsed.expression == #""crash"*"#)
        #expect(parsed.agentNames == ["codex"])
        #expect(parsed.projectNames == ["native"])
        #expect(parsed.filters.roles == [.user])
        #expect(parsed.filters.hasDiff)
        #expect(parsed.filters.includeArchived)
        let after = try #require(parsed.filters.after)
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: after).day == 31)
    }

    @Test func unknownOperatorsAreText() {
        #expect(ParsedSearchQuery(SearchQuery("http://localhost:8080 ")).expression == #""http localhost 8080""#)
        #expect(ParsedSearchQuery(SearchQuery("role:wizard")).expression == #""role wizard"*"#)
        #expect(ParsedSearchQuery(SearchQuery("role:wizard")).isNarrowed == false)
    }

    @Test func onlyFiltersHaveNoExpression() {
        #expect(ParsedSearchQuery(SearchQuery("agent:claude")).expression == nil)
        #expect(ParsedSearchQuery(SearchQuery("  ")).expression == nil)
    }
}
