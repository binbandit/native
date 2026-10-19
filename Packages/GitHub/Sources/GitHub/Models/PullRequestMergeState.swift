import Foundation

/// A merge already arranged for a pull request: waiting in its base branch's merge queue, or set to
/// merge on its own once requirements pass. Lists and the page say so in place of offering a merge.
public enum PullRequestMergeState: Sendable, Hashable {
    /// In the merge queue. `position` is 1 for the next to merge.
    case queued(position: Int?, stage: QueueStage)
    /// Auto-merge is on, with this method.
    case autoMerge(MergeMethod?)

    /// What the queue is doing with an entry, as GitHub names it.
    public enum QueueStage: String, Sendable, Hashable, GitHubEnum {
        case queued = "QUEUED"
        /// The queue is running checks on it merged with the entries ahead.
        case awaitingChecks = "AWAITING_CHECKS"
        /// Its checks passed; it merges when its turn comes.
        case mergeable = "MERGEABLE"
        /// Its checks failed; the queue will remove it.
        case unmergeable = "UNMERGEABLE"
        /// Being merged now.
        case locked = "LOCKED"
        case other
    }

    /// "Queued · position 3", "Checks running in queue", "Merges when checks pass".
    public var summary: String {
        switch self {
        case .queued(let position, let stage):
            let place = position.map { " · position \($0)" } ?? ""
            switch stage {
            case .awaitingChecks: return "Checks running in queue" + place
            case .mergeable: return "Passed in queue, merging next" + place
            case .unmergeable: return "Failing in queue"
            case .locked: return "Merging from queue"
            case .queued, .other: return "Queued" + place
            }
        case .autoMerge: return "Merges when checks pass"
        }
    }

    /// The fields both the list's status query and the page ask for.
    static let fields = "mergeQueueEntry { position state } autoMergeRequest { mergeMethod }"

    struct Payload: Decodable, Sendable, Hashable {
        struct Entry: Decodable, Sendable, Hashable {
            var position: Int?
            var state: String?
        }

        struct AutoMerge: Decodable, Sendable, Hashable {
            var mergeMethod: String?
        }

        var mergeQueueEntry: Entry?
        var autoMergeRequest: AutoMerge?

        var state: PullRequestMergeState? {
            if let entry = mergeQueueEntry {
                return .queued(position: entry.position, stage: QueueStage(wire: entry.state) ?? .queued)
            }
            if let autoMerge = autoMergeRequest {
                return .autoMerge(autoMerge.mergeMethod.flatMap { MergeMethod(rawValue: $0.lowercased()) })
            }
            return nil
        }
    }
}
