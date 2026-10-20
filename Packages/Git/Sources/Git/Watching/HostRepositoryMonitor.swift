import Foundation

/// Watches a repository through the file watcher of the host it lives on, for a project on another
/// machine. The host reports raw paths under each folder it watches; this sorts them the way
/// `FSEventsRepositoryMonitor` sorts FSEvents' paths on this Mac. Paths are compared as git spelled
/// them, since only the host can resolve them.
public struct HostRepositoryMonitor: RepositoryMonitor {
    /// Paths that changed under a watched folder.
    public struct Batch: Hashable, Sendable {
        /// Absolute, spelled from the watched folder as it was asked for.
        public var paths: [String]
        /// Anything under the folder may have changed (the host's watcher lost track, or the
        /// connection dropped for a while). `paths` is then empty.
        public var isOverflow: Bool

        public init(paths: [String], isOverflow: Bool = false) {
            self.paths = paths
            self.isOverflow = isOverflow
        }
    }

    /// Changes under a folder on the host until the consumer stops iterating. A sequence that ends
    /// right away means the host won't watch it. Any sequence will do, so a client's own feed fits
    /// with a `map`.
    public typealias Watch = @Sendable (_ folder: String) -> any AsyncSequence<Batch, Never>

    private let watch: Watch

    public init(watch: @escaping Watch) {
        self.watch = watch
    }

    public func changes(in repository: Repository) -> AsyncStream<RepositoryChange> {
        let classifier = ChangeClassifier(
            root: ChangeClassifier.plainPath(repository.root),
            gitDirectory: ChangeClassifier.plainPath(repository.gitDirectory),
            commonDirectory: ChangeClassifier.plainPath(repository.commonDirectory))
        let watch = watch
        return AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            // Ending iteration cancels the forwarding, which ends every folder's sequence and its watch.
            let forwarding = Task {
                await withDiscardingTaskGroup { group in
                    for folder in classifier.watchedPaths {
                        group.addTask {
                            for await batch in watch(folder) {
                                // An overflow can hide any change, git's own included: rescan.
                                let change =
                                    batch.isOverflow
                                    ? RepositoryChange(gitStateChanged: true) : classifier.classify(batch.paths)
                                if !change.isEmpty { continuation.yield(change) }
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }
}
