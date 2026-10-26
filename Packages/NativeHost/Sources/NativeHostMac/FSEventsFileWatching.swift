import CoreServices
import Foundation
import NativeHost

/// Watches folders on a Mac with FSEvents, set up the way the Git package's `RepositoryWatcher`
/// watches a working tree, minus its git filtering: clients filter for themselves.
public struct FSEventsFileWatching: FileWatching {
    /// How long FSEvents coalesces events before delivering a batch.
    public var latency: TimeInterval

    public init(latency: TimeInterval = 0.2) {
        self.latency = latency
    }

    public func changes(under root: String) async -> AsyncStream<FileWatchBatch> {
        guard let watcher = FolderWatcher(root: root, latency: latency) else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            // The forwarding task keeps the watcher alive; ending iteration cancels it, which
            // releases the watcher and stops its stream.
            let forwarding = Task {
                for await batch in watcher.changes {
                    continuation.yield(batch)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }
}

/// One FSEvents stream on one folder, stopped when released.
private final class FolderWatcher: Sendable {
    let changes: AsyncStream<FileWatchBatch>

    // Only touched in init and deinit, and on `queue` by FSEvents itself.
    nonisolated(unsafe) private let stream: FSEventStreamRef
    private let queue = DispatchQueue(label: "Native.FolderWatcher")
    private let context: Unmanaged<FolderWatcherContext>

    /// Nil when FSEvents can't create a stream for the folder.
    init?(root: String, latency: TimeInterval) {
        let (changes, continuation) = AsyncStream.makeStream(
            of: FileWatchBatch.self, bufferingPolicy: .bufferingNewest(64))
        self.changes = changes
        let context = Unmanaged.passRetained(FolderWatcherContext(continuation: continuation))
        self.context = context
        var streamContext = FSEventStreamContext(
            version: 0, info: context.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        // WatchRoot reports the folder itself moving or going away, which no event inside it shows.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot)
        let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let context = Unmanaged<FolderWatcherContext>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                context.handle(paths.prefix(count), flags: UnsafeBufferPointer(start: flags, count: count))
            },
            &streamContext,
            [root] as CFArray,
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
private final class FolderWatcherContext: @unchecked Sendable {
    let continuation: AsyncStream<FileWatchBatch>.Continuation

    /// Events that mean FSEvents lost track of what happened under the folder.
    private static let lostTrack = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)

    init(continuation: AsyncStream<FileWatchBatch>.Continuation) {
        self.continuation = continuation
    }

    func handle(_ paths: some Sequence<String>, flags: UnsafeBufferPointer<FSEventStreamEventFlags>) {
        let isOverflow = flags.contains { $0 & Self.lostTrack != 0 }
        continuation.yield(FileWatchBatch(paths: isOverflow ? [] : Array(paths), isOverflow: isOverflow))
    }
}
