import ACP
import Foundation
import NativeHostProtocol
import Synchronization

// Folders clients watch (`_native/fs/watch`): the host side of a remote repository's change feed.
// Each watch runs the host's `FileWatching` on the folder and sends what changes, coalesced, as
// `_native/fs/changed`, until the client unwatches it or goes away.
extension HostCore {
    /// Answers once the watcher is running, so the client sees every change it makes after that.
    func watchFiles(_ params: FileWatchParams, for client: ClientLink) async throws {
        let root = try projectPath(params.root, for: client, to: "watch files")
        guard let status = HostFileStatus(path: root, followingLinks: true) else {
            throw HostFileError.notFound(path: params.root)
        }
        guard status.kind == .directory else { throw HostFileError.notADirectory(path: params.root) }
        let changes = await fileWatching.changes(under: root)
        // A client that left while this was on its way, or while the watcher started, would never
        // unwatch it. Dropping the stream stops the watcher.
        guard clients[client.id] != nil else { return }
        client.fileWatches[params.watchID]?.stop()
        client.fileWatches[params.watchID] = HostFileWatch(
            id: params.watchID, root: root, changes: changes, peer: client.peer)
    }

    /// Stops one of the client's own watches; one it doesn't have is already stopped.
    func unwatchFiles(_ watchID: UUID, for client: ClientLink) {
        client.fileWatches.removeValue(forKey: watchID)?.stop()
    }

    /// Stops everything a client watches, once it's gone.
    func stopFileWatches(of client: ClientLink) {
        for watch in client.fileWatches.values {
            watch.stop()
        }
        client.fileWatches = [:]
    }

    var fileWatching: any FileWatching {
        configuration.fileWatching ?? PollingFileWatching()
    }
}

/// One folder a client watches: its watcher's changes, made relative to the folder and coalesced,
/// go to the client as they happen.
final class HostFileWatch: Sendable {
    private let coalescer: FileChangeCoalescer<ContinuousClock>
    private let forwarding: Task<Void, Never>

    init(id: UUID, root: String, changes: AsyncStream<FileWatchBatch>, peer: JSONRPCPeer) {
        let coalescer = FileChangeCoalescer(
            latency: FileChangedNotification.latency, limit: FileChangedNotification.pathLimit
        ) { paths, isOverflow in
            try? peer.notify(
                HostProtocol.Method.fsChanged,
                FileChangedNotification(watchID: id, paths: paths, isOverflow: isOverflow))
        }
        self.coalescer = coalescer
        let prefix = root.hasSuffix("/") ? root : root + "/"
        // Ending the iteration ends the watcher's stream, which stops the watcher.
        forwarding = Task {
            for await batch in changes {
                var relative = FileWatchBatch(paths: [], isOverflow: batch.isOverflow)
                for path in batch.paths {
                    if path == root {
                        relative.paths.append("")
                    } else if path.hasPrefix(prefix) {
                        relative.paths.append(String(path.dropFirst(prefix.count)))
                    } else {
                        // Spelled some other way than the root; the client can't place it, so it rescans.
                        relative.isOverflow = true
                    }
                }
                coalescer.add(relative)
            }
        }
    }

    func stop() {
        forwarding.cancel()
        coalescer.stop()
    }
}

/// Batches changes the way FSEvents does: the first change after a quiet spell goes out at once,
/// later ones at most once every `latency`, each batch without duplicates. Past `limit` paths a
/// batch becomes an overflow, which tells the client to look at everything again.
final class FileChangeCoalescer<C: Clock>: Sendable where C.Duration == Duration {
    typealias Send = @Sendable (_ paths: [String], _ isOverflow: Bool) -> Void

    private struct State {
        var pending: Set<String> = []
        var isOverflow = false
        var lastSent: C.Instant?
        var flush: Task<Void, Never>?
        var isStopped = false

        var hasPending: Bool { isOverflow || !pending.isEmpty }
    }

    private let clock: C
    private let latency: Duration
    private let limit: Int
    private let send: Send
    private let state = Mutex(State())

    init(clock: C, latency: Duration, limit: Int, send: @escaping Send) {
        self.clock = clock
        self.latency = latency
        self.limit = limit
        self.send = send
    }

    func add(_ batch: FileWatchBatch) {
        state.withLock { state in
            guard !state.isStopped else { return }
            if batch.isOverflow {
                state.isOverflow = true
            }
            if !state.isOverflow {
                state.pending.formUnion(batch.paths)
                if state.pending.count > limit {
                    state.isOverflow = true
                }
            }
            if state.isOverflow {
                state.pending = []
            }
            guard state.hasPending, state.flush == nil else { return }
            let now = clock.now
            if let lastSent = state.lastSent, now < lastSent.advanced(by: latency) {
                let deadline = lastSent.advanced(by: latency)
                state.flush = Task { [weak self, clock] in
                    try? await clock.sleep(until: deadline, tolerance: nil)
                    self?.flush()
                }
            } else {
                sendPending(&state, at: now)
            }
        }
    }

    /// Returns pending work so a caller that needs quiescence can wait for its cancellation.
    @discardableResult
    func stop() -> Task<Void, Never>? {
        state.withLock { state in
            let flush = state.flush
            state.isStopped = true
            flush?.cancel()
            state.flush = nil
            return flush
        }
    }

    private func flush() {
        state.withLock { state in
            state.flush = nil
            guard !state.isStopped, state.hasPending else { return }
            sendPending(&state, at: clock.now)
        }
    }

    /// Sent under the lock, so batches leave in the order they were made.
    private func sendPending(_ state: inout State, at now: C.Instant) {
        send(state.isOverflow ? [] : state.pending.sorted(), state.isOverflow)
        state.pending = []
        state.isOverflow = false
        state.lastSent = now
    }
}

extension FileChangeCoalescer where C == ContinuousClock {
    convenience init(latency: Duration, limit: Int, send: @escaping Send) {
        self.init(clock: ContinuousClock(), latency: latency, limit: limit, send: send)
    }
}
