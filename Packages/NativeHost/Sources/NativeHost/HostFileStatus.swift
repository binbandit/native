import Foundation
import NativeHostProtocol

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// What `stat` or `lstat` says about a path, the same on every platform the host runs on.
struct HostFileStatus: Hashable, Sendable {
    var kind: HostFileKind
    var size: Int
    /// Nanoseconds since 1970, to tell writes within the same second apart.
    var modified: Int64
    var inode: UInt64

    /// Nil when nothing is there, or the host can't look.
    init?(path: String, followingLinks: Bool) {
        var info = stat()
        guard (followingLinks ? stat(path, &info) : lstat(path, &info)) == 0 else { return nil }
        self.init(info)
    }

    init?(descriptor: Int32) {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return nil }
        self.init(info)
    }

    private init(_ info: stat) {
        switch info.st_mode & S_IFMT {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symlink
        default: kind = .other
        }
        size = Int(info.st_size)
        #if canImport(Darwin)
        let time = info.st_mtimespec
        #else
        let time = info.st_mtim
        #endif
        modified = Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
        inode = UInt64(info.st_ino)
    }

    var modifiedAt: Date {
        Date(timeIntervalSince1970: Double(modified) / 1_000_000_000)
    }

    /// `name` inside the folder at `folder`, both as the host spells them.
    static func join(_ folder: String, _ name: String) -> String {
        folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }
}
