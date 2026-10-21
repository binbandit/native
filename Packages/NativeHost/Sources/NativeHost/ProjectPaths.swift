import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Where clients may run commands and read files on a host: inside one of its roots (its projects,
/// its sessions' folders, its task worktrees) once every symbolic link, `.` and `..` is resolved.
/// Shared by `_native/exec/*` and `_native/fs/*`, so both draw the line in the same place.
///
/// It keeps the file API and commands' folders where the client means them to be. It isn't a
/// sandbox for commands: a command reads whatever the host's user can, which is why running one
/// takes the `runCommands` grant.
struct ProjectPaths: Sendable {
    enum Refusal: Error, Hashable {
        /// Paths on a host are absolute: there's no folder a relative one could be relative to.
        case notAbsolute(String)
        case outsideProjects(String)
    }

    /// The roots, resolved. Roots that don't exist are left out.
    let roots: [String]

    init(roots: some Sequence<String>) {
        var resolved: [String] = []
        for root in roots where root.hasPrefix("/") {
            guard let real = Self.realPath(root).path, !resolved.contains(real) else { continue }
            resolved.append(real)
        }
        self.roots = resolved
    }

    /// `path` resolved, when that's a root or inside one.
    func resolve(_ path: String) throws(Refusal) -> String {
        guard path.hasPrefix("/") else { throw .notAbsolute(path) }
        guard let resolved = Self.resolvedPath(path), contains(resolved: resolved) else {
            throw .outsideProjects(path)
        }
        return resolved
    }

    /// Whether an already resolved path is a root or inside one.
    func contains(resolved path: String) -> Bool {
        roots.contains { root in
            path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
        }
    }

    /// `path` with every symbolic link, `.` and `..` resolved, the way the file system follows them.
    /// A path that doesn't exist yet resolves through its nearest existing folder, so something about
    /// to be created is judged by where it would land. Nil when it can't be resolved: a component
    /// that isn't a folder, one the host can't search, or a dangling symbolic link, which would land
    /// wherever it points once its target appears.
    static func resolvedPath(_ path: String) -> String? {
        let (real, error) = realPath(path)
        if let real { return real }
        guard error == ENOENT, !isPresent(path) else { return nil }
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        guard let slash = trimmed.lastIndex(of: "/") else { return nil }
        let name = trimmed[trimmed.index(after: slash)...]
        // ".." past a missing folder means nothing the file system would follow.
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        let parent = slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
        guard let resolvedParent = resolvedPath(parent) else { return nil }
        return resolvedParent == "/" ? "/\(name)" : "\(resolvedParent)/\(name)"
    }

    /// Opens a file that `resolve` let through, for reading. No symbolic link is followed anywhere in
    /// the path, so one swapped in after the check can't lead
    /// out of the project. Anything but a regular file is refused: a FIFO would block the read forever.
    static func openForReading(_ resolvedPath: String) throws -> FileHandle {
        #if canImport(Darwin)
        let descriptor = open(resolvedPath, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW_ANY)
        #else
        let descriptor = try openWithoutLinks(resolvedPath)
        #endif
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw POSIXError(.EINVAL)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    #if !canImport(Darwin)
    /// O_NOFOLLOW checks only the last component on Linux. Walk from an open root directory so
    /// each parent is checked too, and a rename cannot redirect the next lookup through a link.
    private static func openWithoutLinks(_ path: String) throws -> Int32 {
        let components = path.split(separator: "/")
        guard path.hasPrefix("/"), let name = components.last,
            !components.contains(where: { $0 == "." || $0 == ".." })
        else { throw POSIXError(.EINVAL) }
        // Traversal needs search permission, not permission to list a directory's contents.
        var directory = open("/", O_PATH | O_CLOEXEC | O_DIRECTORY)
        guard directory >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(directory) }
        for component in components.dropLast() {
            let next = openat(directory, String(component), O_PATH | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            close(directory)
            directory = next
        }
        return openat(directory, String(name), O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW)
    }
    #endif

    private static func realPath(_ path: String) -> (path: String?, error: Int32) {
        guard let resolved = realpath(path, nil) else { return (nil, errno) }
        defer { free(resolved) }
        return (String(cString: resolved), 0)
    }

    /// Whether anything is at `path` itself, a dangling symbolic link included.
    private static func isPresent(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }
}
