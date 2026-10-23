/// The immutable commit chosen for a task, and whether it came from a fresh fetch.
public struct TaskWorktreeBase: Hashable, Sendable {
    public enum LocalReason: Hashable, Sendable {
        case disabled, detached, noRemote, fetchFailed
    }

    public enum Source: Hashable, Sendable {
        case remote
        case local(LocalReason)
    }

    public let commit: String
    public let branch: String?
    public let source: Source
}
