#if os(macOS)
import Foundation

/// Watches repositories on this Mac with FSEvents.
public struct FSEventsRepositoryMonitor: RepositoryMonitor {
    /// How long FSEvents coalesces events before delivering a batch.
    public var latency: TimeInterval

    public init(latency: TimeInterval = 0.2) {
        self.latency = latency
    }

    public func changes(in repository: Repository) -> AsyncStream<RepositoryChange> {
        guard let watcher = RepositoryWatcher(repository: repository, latency: latency) else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            // The forwarding task keeps the watcher alive; ending iteration cancels it, which
            // releases the watcher and stops its stream.
            let forwarding = Task {
                for await change in watcher.changes {
                    continuation.yield(change)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }
}
#endif
