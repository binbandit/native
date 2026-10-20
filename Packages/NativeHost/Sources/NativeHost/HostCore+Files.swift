import ACP
import Foundation
import NativeHostProtocol

// Clients' file requests (`_native/fs/*`), so a client reads a project on this host as it would its
// own. Who may and where is `HostCore+ExecAccess.swift`: the `runCommands` grant, and paths that
// resolve inside the host's projects, sessions' folders or task worktrees. Errors name the path as
// the client sent it.
extension HostCore {
    /// Answers `_native/fs/read`, `list`, `stat`, `watch` and `unwatch`.
    func answerFiles(
        _ message: JSONRPCPeer.Message, from client: ClientLink
    ) async throws -> any Encodable & Sendable {
        typealias Method = HostProtocol.Method
        do {
            switch message.method {
            case Method.fsRead:
                let params = try message.params(as: FileReadParams.self)
                let path = try projectPath(params.path, for: client, to: "read files")
                return try await Self.readFile(path, as: params.path, range: params.range)
            case Method.fsList:
                let params = try message.params(as: FilePathParams.self)
                let path = try projectPath(params.path, for: client, to: "list folders")
                return try await Self.listFolder(path, as: params.path)
            case Method.fsStat:
                let params = try message.params(as: FilePathParams.self)
                let path = try projectPath(params.path, for: client, to: "look at files")
                return try await Self.fileInfo(path, as: params.path)
            case Method.fsWatch:
                try watchFiles(try message.params(as: FileWatchParams.self), for: client)
                return EmptyMessage()
            case Method.fsUnwatch:
                unwatchFiles(try message.params(as: FileUnwatchParams.self).watchID, for: client)
                return EmptyMessage()
            default:
                throw RPCError.methodNotFound(message.method)
            }
        } catch let error as HostFileError {
            throw error.rpcError
        }
    }

    /// Reads off the host actor: a megabyte from a slow disk shouldn't hold up every session.
    @concurrent
    nonisolated private static func readFile(
        _ path: String, as requested: String, range: FileByteRange?
    ) async throws -> FileReadResult {
        let limit = FileReadResult.sizeLimit
        if let range {
            guard range.offset >= 0, range.length >= 0 else {
                throw RPCError(code: -32602, message: "A range's offset and length can't be negative.")
            }
            guard range.length <= limit else {
                throw RPCError(code: -32602, message: "A read returns at most \(limit) bytes; ask for a smaller range.")
            }
        }
        guard let status = HostFileStatus(path: path, followingLinks: true) else {
            throw HostFileError.notFound(path: requested)
        }
        guard status.kind == .file else { throw HostFileError.notAFile(path: requested) }
        let handle: FileHandle
        do {
            handle = try ProjectPaths.openForReading(path)
        } catch let error as POSIXError {
            switch error.code {
            case .ENOENT: throw HostFileError.notFound(path: requested)
            // A link swapped in after the path was checked: it could lead anywhere.
            case .ELOOP: throw HostError.outsideProjects(requested)
            case .EINVAL: throw HostFileError.notAFile(path: requested)
            default: throw error
            }
        }
        defer { try? handle.close() }
        // The open file as it is now, in case it changed since the path was looked at.
        let opened = HostFileStatus(descriptor: handle.fileDescriptor) ?? status
        let size = opened.size
        let offset = min(range?.offset ?? 0, size)
        let length = range?.length ?? size
        guard range != nil || size <= limit else {
            throw HostFileError.tooLarge(path: requested, size: size, limit: limit)
        }
        try handle.seek(toOffset: UInt64(offset))
        let data = length > 0 ? try handle.read(upToCount: min(length, limit)) ?? Data() : Data()
        return FileReadResult(data: data, size: size, modifiedAt: opened.modifiedAt)
    }

    /// Off the host actor too: a stat on a network volume can hang.
    @concurrent
    nonisolated private static func fileInfo(_ path: String, as requested: String) async throws -> HostFileInfo {
        guard let status = HostFileStatus(path: path, followingLinks: true) else {
            throw HostFileError.notFound(path: requested)
        }
        return HostFileInfo(path: path, kind: status.kind, size: status.size, modifiedAt: status.modifiedAt)
    }

    @concurrent
    nonisolated private static func listFolder(_ path: String, as requested: String) async throws -> FileListResult {
        guard let status = HostFileStatus(path: path, followingLinks: true) else {
            throw HostFileError.notFound(path: requested)
        }
        guard status.kind == .directory else { throw HostFileError.notADirectory(path: requested) }
        let names = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
        let entries = names.prefix(FileListResult.entryLimit).map { name in
            let entry = HostFileStatus(path: HostFileStatus.join(path, name), followingLinks: false)
            return HostDirectoryEntry(
                name: name, kind: entry?.kind ?? .other, size: entry?.size ?? 0, modifiedAt: entry?.modifiedAt)
        }
        return FileListResult(entries: entries, isTruncated: names.count > FileListResult.entryLimit)
    }
}
