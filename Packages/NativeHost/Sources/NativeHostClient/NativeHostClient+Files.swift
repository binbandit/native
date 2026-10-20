import ACP
import Foundation
import NativeHostProtocol
import Synchronization

// The host's file requests (`_native/fs/*`). `RemoteFiles` is the API; these are its wire calls, with
// file errors decoded into `HostFileError`.
extension NativeHostClient {
    func readFile(_ params: FileReadParams) async throws -> FileReadResult {
        try await fileCall(HostProtocol.Method.fsRead, params)
    }

    func listFolder(_ path: String) async throws -> FileListResult {
        try await fileCall(HostProtocol.Method.fsList, FilePathParams(path: path))
    }

    func fileInfo(_ path: String) async throws -> HostFileInfo {
        try await fileCall(HostProtocol.Method.fsStat, FilePathParams(path: path))
    }

    func watchFiles(_ params: FileWatchParams) async throws {
        let _: EmptyMessage = try await fileCall(HostProtocol.Method.fsWatch, params)
    }

    func unwatchFiles(_ watchID: UUID) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.fsUnwatch, FileUnwatchParams(watchID: watchID))
    }

    /// The route `_native/fs/changed` takes to the watch it belongs to.
    func fileChanges() -> FileChangeRoute {
        route(HostProtocol.Method.fsChanged, make: FileChangeRoute.init)
    }

    private func fileCall<Result: Decodable & Sendable>(
        _ method: String, _ params: some Encodable & Sendable
    ) async throws -> Result {
        do {
            return try await call(method, params)
        } catch {
            throw HostFileError(error) ?? error
        }
    }
}

/// Hands each `_native/fs/changed` to the watch waiting for it. Changes for a watch nobody follows
/// any more are dropped.
final class FileChangeRoute: HostNotificationRoute {
    typealias Receiver = @Sendable (FileChangedNotification) -> Void

    private let receivers = Mutex<[UUID: Receiver]>([:])

    func add(_ watchID: UUID, _ receiver: @escaping Receiver) {
        receivers.withLock { $0[watchID] = receiver }
    }

    func remove(_ watchID: UUID) {
        receivers.withLock { $0[watchID] = nil }
    }

    func receive(_ message: JSONRPCPeer.Message) async {
        guard let change = try? message.params(as: FileChangedNotification.self) else { return }
        receivers.withLock { $0[change.watchID] }?(change)
    }
}
