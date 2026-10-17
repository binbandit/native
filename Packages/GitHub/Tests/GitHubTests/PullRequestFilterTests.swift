import Foundation
import Testing

@testable import GitHub

struct PullRequestFilterTests {
    /// The real inbox captured from gh: authored and review-requested searches, enriched.
    func inbox() throws -> PullRequestInbox {
        let response = try Fixtures.decode(PullRequestStatus.Response.self, from: "graphql-pull-request-status")
        let statuses = Dictionary(
            uniqueKeysWithValues: response.data.nodes.compactMap { $0?.status }.map { ($0.id, $0) })
        func section(_ name: String) throws -> [PullRequestSummary] {
            try Fixtures.decode([PullRequestSearchResult].self, from: name).map {
                PullRequestSummary($0, status: statuses[$0.id])
            }
        }
        let authored = try section("search-authored")
        // An assignment that duplicates an authored pull request, and one that doesn't.
        var extra = try #require(authored.last)
        extra.url = URL(filePath: "/elsewhere/repo/pull/1")
        extra.repository = "elsewhere/repo"
        return PullRequestInbox(
            authored: authored, reviewRequested: try section("search-review-requested"), assigned: [authored[0], extra])
    }

    @Test func involvementPutsReviewsFirstAndDropsDuplicateAssignments() throws {
        let inbox = try inbox()
        let groups = PullRequestFilter().groups(in: inbox)

        #expect(groups.map(\.id) == [.involvement(.reviewRequested), .involvement(.author), .involvement(.assignee)])
        #expect(groups[0].pullRequests.count == inbox.reviewRequested.count)
        #expect(groups[2].pullRequests.map(\.repository) == ["elsewhere/repo"])
    }

    @Test func assignedGroupDisappearsWhenItAddsNothing() throws {
        var inbox = try inbox()
        inbox.assigned = [inbox.authored[0]]
        #expect(PullRequestFilter().groups(in: inbox).count == 2)
    }

    @Test func emptyReviewGroupStaysToSaySo() throws {
        var inbox = try inbox()
        inbox.reviewRequested = []
        let groups = PullRequestFilter(scope: .all).groups(in: inbox)
        #expect(groups.first?.id == .involvement(.reviewRequested))
        #expect(groups.first?.pullRequests.isEmpty == true)
    }

    @Test func repositoryGroupsAreNewestFirstAndDeduplicated() throws {
        let inbox = try inbox()
        let groups = PullRequestFilter(grouping: .repository).groups(in: inbox)
        let urls = groups.flatMap(\.pullRequests).map(\.url)

        #expect(Set(urls).count == urls.count)
        #expect(urls.count == inbox.all.count)
        let latest = groups.compactMap { $0.pullRequests.first?.updatedAt }
        #expect(latest == latest.sorted(by: >))
        let ohFx = try #require(groups.first { $0.id == .repository("binbandit/oh-fx") })
        #expect(ohFx.pullRequests.count == 4)
    }

    @Test func scopeLimitsToOneInvolvement() throws {
        let inbox = try inbox()
        let groups = PullRequestFilter(scope: .reviewRequested, grouping: .repository).groups(in: inbox)
        #expect(Set(groups.map(\.title)) == Set(inbox.reviewRequested.map(\.repository)))
    }

    @Test func queryMatchesEveryTermAcrossFields() throws {
        let inbox = try inbox()
        func titles(_ query: String) -> [String] {
            PullRequestFilter(query: query).groups(in: inbox).flatMap(\.pullRequests).map(\.title)
        }

        #expect(titles("bifrost cursor") == ["fix(ui): restore pointer cursor on alert dialog buttons"])
        #expect(titles("#2584").count == 1)
        // Branch names match too; the duplicate assignment of the same pull request isn't repeated.
        #expect(titles("ai/tty-5").count == 1)
        #expect(titles("DEPENDENCIES").allSatisfy { $0.hasPrefix("build(deps)") })
        #expect(titles("no-such-thing").isEmpty)
    }

    @Test func draftsCanBeHidden() throws {
        var inbox = try inbox()
        inbox.authored[0].isDraft = true
        let filter = PullRequestFilter(scope: .authored, includesDrafts: false)

        #expect(filter.isNarrowing)
        #expect(filter.groups(in: inbox)[0].pullRequests.count == inbox.authored.count - 1)
    }
}
