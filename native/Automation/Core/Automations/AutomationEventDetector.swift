import Foundation

/// Turns two GitHub polls into events, so automations can react to pull requests without webhooks.
/// The first poll is a baseline: everything already open when Native starts watching is old news.
nonisolated enum AutomationEventDetector {
    static func occurrences(from previous: [PullRequestSnapshot]?, to current: [PullRequestSnapshot], at now: Date) -> [AutomationOccurrence] {
        guard let previous else { return [] }
        let before = Dictionary(previous.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [AutomationOccurrence] = []
        for pullRequest in current {
            func event(_ kind: AutomationEventKind, _ key: String) {
                found.append(AutomationOccurrence(
                    kind: kind, key: "\(kind.rawValue):\(pullRequest.url.absoluteString):\(key)", repository: pullRequest.repository,
                    subject: pullRequest.subject, url: pullRequest.url, occurredAt: now
                ))
            }
            let stamp = String(Int(pullRequest.updatedAt.timeIntervalSince1970))
            guard let old = before[pullRequest.url] else {
                if pullRequest.isAuthored { event(.pullRequestOpened, "opened") }
                if pullRequest.isReviewRequested { event(.reviewRequested, stamp) }
                if pullRequest.hasFailingChecks { event(.checksFailed, stamp) }
                continue
            }
            if pullRequest.updatedAt > old.updatedAt { event(.pullRequestUpdated, stamp) }
            if pullRequest.isReviewRequested, !old.isReviewRequested { event(.reviewRequested, stamp) }
            if pullRequest.hasFailingChecks, !old.hasFailingChecks { event(.checksFailed, stamp) }
        }
        return found
    }
}
