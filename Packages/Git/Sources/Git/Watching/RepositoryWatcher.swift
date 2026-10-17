import CoreServices
import Foundation

/// Watches a working tree with FSEvents. Changes inside git directories are dropped, except the
/// ones that change what `status()` reports: HEAD, the index and branch refs.
public final class RepositoryWatcher: Sendable {
    /// Batches of changes, already coalesced by FSEvents over `latency`.
    public let changes: AsyncStream<RepositoryChange>

    // Only touched in init and deinit, and on `queue` by FSEvents itself.
    nonisolated(unsafe) private let stream: FSEventStreamRef
    private let queue = DispatchQueue(label: "Native.RepositoryWatcher")
    private let context: Unmanaged<WatcherContext>

    /// `nil` when FSEvents can't create a stream for the repository's folders.
    public init?(repository: Repository, latency: TimeInterval = 0.2) {
        let (changes, continuation) = AsyncStream.makeStream(of: RepositoryChange.self, bufferingPolicy: .bufferingNewest(64))
        self.changes = changes

        let classifier = ChangeClassifier(repository: repository)
        let context = Unmanaged.passRetained(WatcherContext(classifier: classifier, continuation: continuation))
        self.context = context
        var streamContext = FSEventStreamContext(version: 0, info: context.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, _, _ in
                guard let info else { return }
                let context = Unmanaged<WatcherContext>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                context.handle(paths.prefix(count))
            },
            &streamContext,
            classifier.watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
        guard let created else {
            context.release()
            return nil
        }
        stream = created
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        let stream = stream
        let context = context
        queue.sync {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        context.takeUnretainedValue().continuation.finish()
        context.release()
    }
}

/// Owned by the stream's callback; only used on the watcher's queue.
private final class WatcherContext: @unchecked Sendable {
    let classifier: ChangeClassifier
    let continuation: AsyncStream<RepositoryChange>.Continuation

    init(classifier: ChangeClassifier, continuation: AsyncStream<RepositoryChange>.Continuation) {
        self.classifier = classifier
        self.continuation = continuation
    }

    func handle(_ paths: some Sequence<String>) {
        let change = classifier.classify(paths)
        if !change.isEmpty { continuation.yield(change) }
    }
}
