import Foundation
import NativeHostProtocol

/// How a host watches folders for `_native/fs/watch`: FSEvents on a Mac (`NativeHostMac`), polling
/// where a platform has nothing better. Set in `HostCore.Configuration.fileWatching`.
public protocol FileWatching: Sendable {
    /// Changes under `root` (absolute, symbolic links resolved) from the moment this returns until the
    /// consumer stops iterating, which stops the watching. A client told its watch has started can
    /// rely on seeing every change it makes from then on.
    func changes(under root: String) async -> AsyncStream<FileWatchBatch>
}

/// Paths that changed together, as the watcher reports them.
public struct FileWatchBatch: Hashable, Sendable {
    /// Absolute, under the watched root.
    public var paths: [String]
    /// The watcher lost track (events dropped, the root moved, too much to tell apart): anything
    /// under the root may have changed.
    public var isOverflow: Bool

    public init(paths: [String], isOverflow: Bool = false) {
        self.paths = paths
        self.isOverflow = isOverflow
    }
}

/// Watches by looking: walks the folder every `interval` and reports what differs from the last
/// walk. Portable, and fine for a project; a platform with change notifications (inotify) should get
/// its own `FileWatching`.
public struct PollingFileWatching: FileWatching {
    public var interval: Duration
    /// A walk stops after this many entries, so a huge tree can't keep the host busy. Incomplete
    /// coverage reports an overflow every poll, since changes beyond the scanned prefix are unknown.
    public var entryLimit: Int

    public init(interval: Duration = .seconds(2), entryLimit: Int = 200_000) {
        self.interval = interval
        self.entryLimit = entryLimit
    }

    public func changes(under root: String) async -> AsyncStream<FileWatchBatch> {
        let (interval, entryLimit) = (interval, entryLimit)
        // Later walks are compared with this one, so a change made after this returns can't be in it.
        let baseline = await Self.walk(root, entryLimit: entryLimit)
        let (stream, continuation) = AsyncStream.makeStream(
            of: FileWatchBatch.self, bufferingPolicy: .bufferingNewest(16))
        let polling = Task.detached {
            var previous = baseline
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }
                let current = FolderSnapshot(root: root, entryLimit: entryLimit)
                if let batch = previous.changes(to: current) {
                    continuation.yield(batch)
                }
                previous = current
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in polling.cancel() }
        return stream
    }

    /// Off the caller's executor: a big tree takes a while, and the host actor has sessions to run.
    @concurrent
    private static func walk(_ root: String, entryLimit: Int) async -> FolderSnapshot {
        FolderSnapshot(root: root, entryLimit: entryLimit)
    }
}

/// Every path under a folder with what `lstat` says about it. Symbolic links are recorded, never
/// followed, so a walk stays inside the folder and can't loop.
struct FolderSnapshot {
    private(set) var entries: [String: HostFileStatus] = [:]
    /// The walk stopped at the entry limit.
    private(set) var isTruncated = false

    init(root: String, entryLimit: Int) {
        guard let status = HostFileStatus(path: root, followingLinks: false) else { return }
        entries[root] = status
        var folders = status.kind == .directory ? [root] : []
        while let folder = folders.popLast() {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for name in names {
                guard entries.count < entryLimit else {
                    isTruncated = true
                    return
                }
                let path = HostFileStatus.join(folder, name)
                guard let status = HostFileStatus(path: path, followingLinks: false) else { continue }
                entries[path] = status
                if status.kind == .directory {
                    folders.append(path)
                }
            }
        }
    }

    /// What changed between complete walks, or nil when nothing did. Incomplete coverage always
    /// overflows. A folder's timestamp is ignored since changes to its entries are listed separately.
    func changes(to newer: FolderSnapshot) -> FileWatchBatch? {
        // An unchanged prefix says nothing about edits to existing files beyond the scan cap.
        if isTruncated || newer.isTruncated { return FileWatchBatch(paths: [], isOverflow: true) }
        var paths: [String] = []
        for (path, status) in newer.entries {
            guard let old = entries[path] else {
                paths.append(path)
                continue
            }
            let isSameFolder =
                old.kind == .directory && status.kind == .directory && old.inode == status.inode
            if !isSameFolder, old != status {
                paths.append(path)
            }
        }
        for path in entries.keys where newer.entries[path] == nil {
            paths.append(path)
        }
        guard !paths.isEmpty else { return nil }
        return FileWatchBatch(paths: paths.sorted())
    }
}
