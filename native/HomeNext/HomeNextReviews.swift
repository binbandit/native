import Foundation
import GitHub

/// GitHub pull requests waiting on the user's review, as Home's one row for all of them.
struct HomeNextReviews: Equatable {
    let pullRequests: [PullRequestSummary]

    init?(_ pullRequests: [PullRequestSummary]) {
        guard !pullRequests.isEmpty else { return nil }
        self.pullRequests = pullRequests.sorted { $0.updatedAt < $1.updatedAt }
    }

    /// "2 pull requests wait on your review"
    var title: String {
        pullRequests.count == 1
            ? "A pull request waits on your review"
            : "\(pullRequests.count) pull requests wait on your review"
    }

    /// "#61 perf(transcript): reuse row heights while streaming, and #212 in pier"
    var detail: String {
        guard let first = pullRequests.first else { return "" }
        let lead = "#\(first.number) \(first.title)"
        let others = pullRequests.dropFirst()
        guard let second = others.first else { return lead }
        if others.count > 1 { return "\(lead), and \(others.count) more" }
        let place = second.repository == first.repository ? "" : " in \(Self.name(of: second.repository))"
        return "\(lead), and #\(second.number)\(place)"
    }

    /// The longest wait sets the row's age.
    var since: Date? { pullRequests.first?.updatedAt }

    private static func name(of repository: String) -> String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}
