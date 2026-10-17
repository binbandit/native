import Foundation

/// What the pull request list shows and how it groups it.
public struct PullRequestFilter: Sendable, Hashable {
    public enum Scope: String, Sendable, Hashable, CaseIterable {
        case all
        case authored
        case reviewRequested
        case assigned
    }

    public enum Grouping: String, Sendable, Hashable, CaseIterable {
        /// Review requested, then the user's own, then assigned.
        case involvement
        /// One group per repository, the most recently active first.
        case repository
    }

    public var scope: Scope
    public var grouping: Grouping
    /// Words that must all appear in the title, `owner/name#number`, branch, author or a label.
    public var query: String
    public var includesDrafts: Bool

    public init(scope: Scope = .all, grouping: Grouping = .involvement, query: String = "", includesDrafts: Bool = true) {
        self.scope = scope
        self.grouping = grouping
        self.query = query
        self.includesDrafts = includesDrafts
    }

    /// Whether anything narrows the list beyond its scope.
    public var isNarrowing: Bool {
        !terms.isEmpty || !includesDrafts
    }

    public func matches(_ pullRequest: PullRequestSummary) -> Bool {
        guard includesDrafts || !pullRequest.isDraft else { return false }
        let terms = terms
        guard !terms.isEmpty else { return true }
        let haystack = [
            pullRequest.title, pullRequest.reference, "#\(pullRequest.number)", pullRequest.headRefName ?? "",
            pullRequest.author?.login ?? "",
        ] + pullRequest.labels.map(\.name)
        return terms.allSatisfy { term in haystack.contains { $0.localizedCaseInsensitiveContains(term) } }
    }

    /// The groups to show, in order. Under `.involvement` the review and authored groups are
    /// always present (empty ones say so), while "assigned" only appears when it adds pull requests
    /// the other two don't already show, since most assignments are self-assignments.
    public func groups(in inbox: PullRequestInbox) -> [PullRequestGroup] {
        switch grouping {
        case .involvement: involvementGroups(in: inbox)
        case .repository: repositoryGroups(in: inbox)
        }
    }

    private var terms: [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func involvementGroups(in inbox: PullRequestInbox) -> [PullRequestGroup] {
        switch scope {
        case .authored:
            return [PullRequestGroup(.involvement(.author), inbox.authored.filter(matches))]
        case .reviewRequested:
            return [PullRequestGroup(.involvement(.reviewRequested), inbox.reviewRequested.filter(matches))]
        case .assigned:
            return [PullRequestGroup(.involvement(.assignee), inbox.assigned.filter(matches))]
        case .all:
            let shown = Set((inbox.reviewRequested + inbox.authored).map(\.url))
            let assigned = inbox.assigned.filter { !shown.contains($0.url) }.filter(matches)
            return [
                PullRequestGroup(.involvement(.reviewRequested), inbox.reviewRequested.filter(matches)),
                PullRequestGroup(.involvement(.author), inbox.authored.filter(matches)),
            ] + (assigned.isEmpty ? [] : [PullRequestGroup(.involvement(.assignee), assigned)])
        }
    }

    private func repositoryGroups(in inbox: PullRequestInbox) -> [PullRequestGroup] {
        let pullRequests: [PullRequestSummary] = switch scope {
        case .all: inbox.all
        case .authored: inbox.authored
        case .reviewRequested: inbox.reviewRequested
        case .assigned: inbox.assigned
        }
        let byRepository = Dictionary(grouping: pullRequests.filter(matches), by: \.repository)
        return byRepository
            .map { PullRequestGroup(.repository($0.key), $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { lhs, rhs in
                let lhsLatest = lhs.pullRequests.first?.updatedAt ?? .distantPast
                let rhsLatest = rhs.pullRequests.first?.updatedAt ?? .distantPast
                return lhsLatest == rhsLatest ? lhs.title < rhs.title : lhsLatest > rhsLatest
            }
    }
}
