import Foundation

extension Repository {
    /// Changes to the working tree and git state, from the monitor of the machine it's on, until
    /// the consumer stops iterating.
    public func changes() -> AsyncStream<RepositoryChange> {
        git.monitor.changes(in: self)
    }
}
