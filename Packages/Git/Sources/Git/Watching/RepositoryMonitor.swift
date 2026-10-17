import Foundation

/// Watches a repository for changes. Separate from running commands because watching is
/// different per machine: FSEvents on this Mac, a host's own watcher for a remote repository.
public protocol RepositoryMonitor: Sendable {
    /// Batches of changes until the consumer stops iterating. A monitor that can't watch the
    /// repository returns a stream that finishes right away.
    func changes(in repository: Repository) -> AsyncStream<RepositoryChange>
}
