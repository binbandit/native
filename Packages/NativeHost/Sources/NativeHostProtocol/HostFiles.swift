import ACP
import Foundation

// A host's project files for its clients (docs/durability.md, "Files"): reading them, listing
// folders and watching them for changes, so a client shows diffs, file lists and live status for a
// project on another machine. Only clients with the `runCommands` grant may, and every path must
// resolve, symbolic links included, inside one of the host's projects, a session's folder or its
// task worktrees.

extension HostProtocol.Method {
    public static let fsRead = "_native/fs/read"
    public static let fsList = "_native/fs/list"
    public static let fsStat = "_native/fs/stat"
    public static let fsWatch = "_native/fs/watch"
    public static let fsUnwatch = "_native/fs/unwatch"
    /// Host → client: files changed under a folder the client watches.
    public static let fsChanged = "_native/fs/changed"
}

/// What a path on the host is.
public enum HostFileKind: String, WireEnum {
    case file
    case directory
    /// Only in listings, which never follow links; `stat` reports what a link leads to.
    case symlink
    /// A socket, a pipe or a device: nothing a client reads.
    case other
    case unknown
}

// MARK: - Reading

public struct FileReadParams: Codable, Sendable {
    /// Absolute, on the host.
    public var path: String
    /// Part of the file. Without it, the whole file, which must fit in one answer.
    public var range: FileByteRange?

    public init(path: String, range: FileByteRange? = nil) {
        self.path = path
        self.range = range
    }
}

public struct FileByteRange: Codable, Hashable, Sendable {
    public var offset: Int
    /// At most `FileReadResult.sizeLimit`. A range past the end of the file reads what's there.
    public var length: Int

    public init(offset: Int, length: Int) {
        self.offset = offset
        self.length = length
    }
}

public struct FileReadResult: Codable, Hashable, Sendable {
    public var data: Data
    /// The whole file's size, so a client reading in ranges knows when it has all of it.
    public var size: Int
    public var modifiedAt: Date?

    public init(data: Data, size: Int, modifiedAt: Date?) {
        self.data = data
        self.size = size
        self.modifiedAt = modifiedAt
    }

    /// The most one answer carries, so a large file never holds up a slow connection's other
    /// traffic for long. Bigger files are read in ranges (`RemoteFiles.data(at:limit:)` does that).
    public static let sizeLimit = 1 << 20
}

// MARK: - Listing and stat

/// `_native/fs/list` and `_native/fs/stat`.
public struct FilePathParams: Codable, Sendable {
    /// Absolute, on the host.
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

/// What `stat` found at a path, symbolic links followed.
public struct HostFileInfo: Codable, Hashable, Sendable {
    /// Where the path led on the host, with symbolic links and `..` resolved.
    public var path: String
    public var kind: HostFileKind
    public var size: Int
    public var modifiedAt: Date?

    public init(path: String, kind: HostFileKind, size: Int, modifiedAt: Date?) {
        self.path = path
        self.kind = kind
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

/// One entry of a folder, as it is in the folder: a link is a `symlink`, never what it points to.
public struct HostDirectoryEntry: Codable, Hashable, Sendable {
    public var name: String
    public var kind: HostFileKind
    public var size: Int
    public var modifiedAt: Date?

    public init(name: String, kind: HostFileKind, size: Int, modifiedAt: Date?) {
        self.name = name
        self.kind = kind
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public struct FileListResult: Codable, Hashable, Sendable {
    /// Sorted by name.
    public var entries: [HostDirectoryEntry]
    /// The folder has more than `entryLimit` entries; these are the first by name.
    public var isTruncated: Bool

    public init(entries: [HostDirectoryEntry], isTruncated: Bool) {
        self.entries = entries
        self.isTruncated = isTruncated
    }

    public static let entryLimit = 10_000
}

// MARK: - Watching

/// Starts sending `_native/fs/changed` for a folder until the client unwatches it or goes away.
public struct FileWatchParams: Codable, Sendable {
    /// Chosen by the client, so it can route changes that arrive before the answer.
    public var watchID: UUID
    /// An absolute folder on the host.
    public var root: String

    public init(watchID: UUID = UUID(), root: String) {
        self.watchID = watchID
        self.root = root
    }
}

public struct FileUnwatchParams: Codable, Sendable {
    public var watchID: UUID

    public init(watchID: UUID) {
        self.watchID = watchID
    }
}

/// Changes under a watched folder, coalesced the way FSEvents does: the first change after a quiet
/// spell goes out at once, and the ones after it at most once every `latency`.
public struct FileChangedNotification: Codable, Hashable, Sendable {
    public var watchID: UUID
    /// Relative to the watched folder, as the client spelled it; "" is the folder itself.
    public var paths: [String]
    /// More changed than `pathLimit`, or the watcher lost track (events dropped, the folder moved):
    /// anything under the folder may have changed. `paths` is then empty.
    public var isOverflow: Bool

    public init(watchID: UUID, paths: [String], isOverflow: Bool) {
        self.watchID = watchID
        self.paths = paths
        self.isOverflow = isOverflow
    }

    public static let pathLimit = 1_000
    public static let latency = Duration.milliseconds(200)
}

// MARK: - Errors

/// Why a file request failed, beyond the grant and the path being outside the host's projects
/// (`HostErrorCode.notAuthorized`, `.outsideProjects`). It travels as a host error whose `data`
/// also carries the path and, for `tooLarge`, the sizes.
public enum HostFileError: Error, Hashable, Sendable, LocalizedError {
    case notFound(path: String)
    case tooLarge(path: String, size: Int, limit: Int)
    case notAFile(path: String)
    case notADirectory(path: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path): "Nothing is at \(path) on the host."
        case .tooLarge(let path, let size, let limit):
            "\(path) is \(size) bytes, over the \(limit)-byte limit for reading it."
        case .notAFile(let path): "\(path) isn't a file."
        case .notADirectory(let path): "\(path) isn't a folder."
        }
    }

    public var code: HostErrorCode {
        switch self {
        case .notFound: .fileNotFound
        case .tooLarge: .fileTooLarge
        case .notAFile: .notAFile
        case .notADirectory: .notADirectory
        }
    }

    public var path: String {
        switch self {
        case .notFound(let path), .tooLarge(let path, _, _), .notAFile(let path), .notADirectory(let path): path
        }
    }

    public var rpcError: RPCError {
        var data: [String: JSONValue] = ["hostError": .string(code.rawValue), "path": .string(path)]
        if case .tooLarge(_, let size, let limit) = self {
            data["size"] = .number(Double(size))
            data["limit"] = .number(Double(limit))
        }
        return RPCError(code: code.code, message: errorDescription ?? "File error", data: .object(data))
    }

    /// The file error `error` is, or nil for anything else.
    public init?(_ error: any Error) {
        guard let error = error as? RPCError, let code = HostErrorCode(error),
            let path = error.data?["path"]?.stringValue
        else { return nil }
        switch code {
        case .fileNotFound: self = .notFound(path: path)
        case .fileTooLarge:
            guard case .number(let size)? = error.data?["size"], case .number(let limit)? = error.data?["limit"] else {
                return nil
            }
            self = .tooLarge(path: path, size: Int(size), limit: Int(limit))
        case .notAFile: self = .notAFile(path: path)
        case .notADirectory: self = .notADirectory(path: path)
        default: return nil
        }
    }
}
