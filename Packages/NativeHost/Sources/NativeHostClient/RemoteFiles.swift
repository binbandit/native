import ACP
import Foundation
import NativeHostProtocol

/// A host's files, from this device: what a client uses wherever it would read a project's files from
/// its own disk or watch them, for a project that lives on that host. Paths are absolute on the host
/// and must be inside one of its projects, sessions' folders or task worktrees (symbolic links
/// resolved); everything here takes the `runCommands` grant.
///
/// File problems throw `HostFileError`; a refusal throws the host's error (`HostErrorCode`
/// `.notAuthorized` or `.outsideProjects`), and a dropped connection `NativeHostClient.Failure`.
public struct RemoteFiles: Sendable {
    public let client: NativeHostClient

    public init(client: NativeHostClient) {
        self.client = client
    }

    public enum Failure: Error, Hashable, LocalizedError {
        /// The file kept changing while it was read in pieces.
        case changedWhileReading(String)

        public var errorDescription: String? {
            switch self {
            case .changedWhileReading(let path): "\(path) kept changing while Native read it; try again."
            }
        }
    }

    /// One read: the whole file when it's at most `FileReadResult.sizeLimit`, or `range` of it.
    public func read(_ path: String, range: FileByteRange? = nil) async throws -> FileReadResult {
        try await client.readFile(FileReadParams(path: path, range: range))
    }

    /// The whole file, read in pieces when it's bigger than one answer carries. Throws
    /// `HostFileError.tooLarge` past `limit`, without reading the rest.
    public func data(at path: String, limit: Int = 16 << 20) async throws -> Data {
        let piece = min(FileReadResult.sizeLimit, max(limit, 0))
        // Pieces of a file that changes between them don't fit together: start again, a few times.
        for _ in 0..<3 {
            let first = try await read(path, range: FileByteRange(offset: 0, length: piece))
            guard first.size <= limit else { throw HostFileError.tooLarge(path: path, size: first.size, limit: limit) }
            var data = first.data
            var isWhole = true
            while data.count < first.size {
                let next = try await read(path, range: FileByteRange(offset: data.count, length: piece))
                guard next.size == first.size, next.modifiedAt == first.modifiedAt, !next.data.isEmpty else {
                    isWhole = false
                    break
                }
                data.append(next.data)
            }
            if isWhole { return data }
        }
        throw Failure.changedWhileReading(path)
    }

    /// What's at `path`, symbolic links followed, or nil when nothing is.
    public func info(at path: String) async throws -> HostFileInfo? {
        do {
            return try await client.fileInfo(path)
        } catch HostFileError.notFound {
            return nil
        }
    }

    /// The folder's entries by name; links are listed as links.
    public func entries(in folder: String) async throws -> FileListResult {
        try await client.listFolder(folder)
    }

    /// Changes under `root`, a folder on the host, until the consumer stops iterating; like FSEvents,
    /// coalesced and sometimes an overflow that means "look at everything again". The watch outlives
    /// dropped connections and host restarts: it starts again on each new connection, followed by
    /// an overflow, since changes in between went unseen. A watch the host refuses (no grant, not a
    /// folder in its projects) finishes the stream.
    public func changes(under root: String) -> AsyncStream<RemoteFileChange> {
        let client = client
        var root = root
        while root.count > 1, root.hasSuffix("/") { root.removeLast() }
        let (stream, continuation) = AsyncStream.makeStream(
            of: RemoteFileChange.self, bufferingPolicy: .bufferingNewest(64))
        let watching = Task { [root] in
            let watchID = UUID()
            let route = await client.fileChanges()
            route.add(watchID) { change in
                continuation.yield(RemoteFileChange(change, under: root))
            }
            // A host forgets a client's watches when it goes, so every new connection watches again.
            let (connections, connected) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
            let handler = await client.addEventHandler { event in
                if case .connection(.connected) = event { connected.yield() }
            }
            if await client.hostInfo != nil { connected.yield() }
            var hasWatched = false
            for await _ in connections {
                do {
                    try await client.watchFiles(FileWatchParams(watchID: watchID, root: root))
                } catch  where NativeHostClient.isConnectionLoss(error) {
                    continue
                } catch {
                    break
                }
                if hasWatched {
                    continuation.yield(RemoteFileChange(paths: [], isOverflow: true))
                }
                hasWatched = true
            }
            route.remove(watchID)
            await client.removeEventHandler(handler)
            continuation.finish()
            if hasWatched {
                try? await client.unwatchFiles(watchID)
            }
        }
        continuation.onTermination = { _ in watching.cancel() }
        return stream
    }
}

/// Paths that changed under a watched folder on a host.
public struct RemoteFileChange: Hashable, Sendable {
    /// Absolute on the host, spelled from the watched folder as the caller gave it.
    public var paths: [String]
    /// Anything under the folder may have changed: more changed than the host lists, its watcher lost
    /// track, or the connection dropped for a while. `paths` is then empty.
    public var isOverflow: Bool

    public init(paths: [String], isOverflow: Bool) {
        self.paths = paths
        self.isOverflow = isOverflow
    }

    init(_ notification: FileChangedNotification, under root: String) {
        let prefix = root == "/" ? "/" : root + "/"
        paths = notification.paths.map { $0.isEmpty ? root : prefix + $0 }
        isOverflow = notification.isOverflow
    }
}
