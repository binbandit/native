#if os(macOS) || os(Linux)
import Foundation

#if os(macOS)
import Darwin
#endif

extension WorktreeClone {
    /// No byte-copy fallback: a large cache must never silently become a large duplicate.
    func perform(supportsClones check: ((URL, URL) -> Bool)? = nil) throws -> Report {
        var report = Report()
        #if os(macOS)
        let sourceFD = try Self.openDirectory(source.path(percentEncoded: false))
        defer { close(sourceFD) }
        let destinationFD = try Self.openDirectory(destination.path(percentEncoded: false))
        defer { close(destinationFD) }
        let sourcePath = try Self.canonicalPath(sourceFD)
        let taskPath = try Self.canonicalPath(destinationFD)
        guard !Self.contains(taskPath, in: sourcePath), !Self.contains(sourcePath, in: taskPath) else {
            throw CommandError.refused("Warm worktrees need separate project and worktree folders.")
        }
        guard check?(source, destination) ?? Self.supportsClones(sourceFD, destinationFD) else {
            report.unsupported = true
            return report
        }
        for path in paths {
            try Task.checkCancellation()
            guard let components = Self.relativeComponents(path), let name = components.last else {
                report.skipped.append(path)
                continue
            }
            do {
                let from = try Self.parentDirectory(sourceFD, components: components.dropLast(), create: false)
                defer { close(from) }
                let to = try Self.parentDirectory(destinationFD, components: components.dropLast(), create: true)
                defer { close(to) }
                var existing = stat()
                guard fstatat(to, name, &existing, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                    throw CommandError.refused("The destination already exists.")
                }
                if directories.contains(path) {
                    var sourceInfo = stat()
                    guard fstatat(from, name, &sourceInfo, AT_SYMLINK_NOFOLLOW) == 0,
                        sourceInfo.st_mode & S_IFMT == S_IFDIR
                    else { throw CommandError.refused("The selected cache isn't a directory.") }
                }
                var created = false
                do {
                    try Self.cloneEntry(name, from: from, to: to, created: &created)
                    // Package links may be copied after their executables. Validate the completed
                    // task tree so preserved raw links cannot use a different checkout-side chain.
                    try Self.validateClonedLinks(name, in: to, taskPath: taskPath)
                    report.cloned.append(path)
                } catch {
                    if created { Self.removeEntry(name, in: to) }
                    throw error
                }
            } catch {
                if error is CancellationError { throw error }
                report.skipped.append(path)
            }
        }
        #else
        report.unsupported = true
        #endif
        return report
    }

    #if os(macOS)
    private static func relativeComponents(_ path: String) -> [String]? {
        // POSIX separators are bytes. A combining mark can hide a slash from Character splitting.
        let components = path.utf8.split(separator: UInt8(ascii: "/"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        guard components.allSatisfy({ isEntryName($0) && $0.lowercased() != ".git" }) else { return nil }
        return components
    }

    private static func isEntryName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.utf8.contains { $0 == 0 || $0 == UInt8(ascii: "/") }
    }

    private static func canonicalPath(_ descriptor: Int32) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { throw posixError() }
        // Keep the filesystem's spelling as bytes, without Swift's Unicode equivalence rules.
        return Array(buffer.prefix(while: { $0 != 0 }))
    }

    private static func contains(_ path: [UInt8], in root: [UInt8]) -> Bool {
        path == root || path.starts(with: root + (root.last == UInt8(ascii: "/") ? [] : [UInt8(ascii: "/")]))
    }

    private static func supportsClones(_ source: Int32, _ destination: Int32) -> Bool {
        var from = statfs()
        var to = statfs()
        guard fstatfs(source, &from) == 0, fstatfs(destination, &to) == 0
        else { return false }
        let apfs = withUnsafeBytes(of: from.f_fstypename) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self) == "apfs"
        }
        return apfs && from.f_fsid.val.0 == to.f_fsid.val.0 && from.f_fsid.val.1 == to.f_fsid.val.1
    }

    private static func openDirectory(_ path: String, at parent: Int32 = AT_FDCWD) throws -> Int32 {
        guard parent == AT_FDCWD || isEntryName(path) else {
            throw CommandError.refused("A directory lookup needs one filesystem component.")
        }
        let descriptor = openat(parent, path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        return descriptor
    }

    private static func parentDirectory(_ root: Int32, components: ArraySlice<String>, create: Bool) throws -> Int32 {
        var descriptor = dup(root)
        guard descriptor >= 0 else { throw posixError() }
        do {
            for part in components {
                guard isEntryName(part) else {
                    throw CommandError.refused("A directory lookup needs one filesystem component.")
                }
                if create, mkdirat(descriptor, part, 0o755) != 0, errno != EEXIST { throw posixError() }
                let next = try openDirectory(part, at: descriptor)
                close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func cloneEntry(
        _ name: String, from source: Int32, to destination: Int32, created: inout Bool
    ) throws {
        try Task.checkCancellation()
        guard isEntryName(name) else { throw CommandError.refused("A clone needs one filesystem component.") }
        var info = stat()
        guard fstatat(source, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            let from = try openDirectory(name, at: source)
            defer { close(from) }
            guard mkdirat(destination, name, 0o755) == 0 else { throw posixError() }
            created = true
            let to = try openDirectory(name, at: destination)
            defer { close(to) }
            try forEachEntry(in: from) { child in
                if child.lowercased() == ".git" {
                    // Recognize Git metadata on case-insensitive volumes as well as case-sensitive ones.
                    // SwiftPM caches may contain standalone checkouts, but not Git redirects.
                    var metadata = stat()
                    guard fstatat(from, child, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
                        metadata.st_mode & S_IFMT == S_IFDIR
                    else { throw CommandError.refused("A cached checkout uses an external git directory.") }
                }
                // Local env files are selected separately by Git after the user opts in.
                guard !child.hasPrefix(".env") else { return }
                var childCreated = false
                try cloneEntry(child, from: from, to: to, created: &childCreated)
                if child.lowercased() == ".git" {
                    // Inspect the private copy so source edits during cloning cannot bypass validation.
                    let gitDirectory = try openDirectory(child, at: to)
                    defer { close(gitDirectory) }
                    try validateGitMetadata(gitDirectory)
                }
            }
            guard fchmod(to, info.st_mode & 0o777) == 0 else { throw posixError() }
        case S_IFLNK:
            var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
            let count = readlinkat(source, name, &buffer, buffer.count)
            guard count > 0, count < buffer.count else { throw posixError() }
            guard let link = String(bytes: buffer.prefix(count), encoding: .utf8) else {
                throw CommandError.refused("A cache contains a link with an unsupported encoding.")
            }
            guard symlinkat(link, destination, name) == 0 else { throw posixError() }
            created = true
        case S_IFREG:
            let file = openat(source, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard file >= 0 else { throw posixError() }
            defer { close(file) }
            var opened = stat()
            guard fstat(file, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG else { throw posixError() }
            guard fclonefileat(file, destination, name, 0) == 0 else { throw posixError() }
            created = true
        default:
            throw CommandError.refused("A cache contains a special file.")
        }
    }

    private static func validateClonedLinks(_ name: String, in parent: Int32, taskPath: [UInt8]) throws {
        try Task.checkCancellation()
        guard isEntryName(name) else { throw CommandError.refused("A link lookup needs one filesystem component.") }
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw posixError() }
        if info.st_mode & S_IFMT == S_IFDIR {
            let directory = try openDirectory(name, at: parent)
            defer { close(directory) }
            try forEachEntry(in: directory) { child in
                try validateClonedLinks(child, in: directory, taskPath: taskPath)
            }
        } else if info.st_mode & S_IFMT == S_IFLNK {
            // Only this metadata-only lookup follows links. The kernel resolves the actual finished
            // task chain, including parent traversal, case and Unicode. No file contents are read.
            guard fstatat(parent, name, &info, 0) == 0,
                info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFREG
            else { throw CommandError.refused("A cache contains a link to a special file.") }
            // Nonblocking also covers a target replaced with a FIFO after the metadata check.
            let target = openat(parent, name, O_EVTONLY | O_NONBLOCK | O_CLOEXEC)
            guard target >= 0 else { throw posixError() }
            defer { close(target) }
            let resolved = try canonicalPath(target)
            guard fstat(target, &info) == 0,
                info.st_mode & S_IFMT == S_IFDIR || info.st_mode & S_IFMT == S_IFREG,
                contains(resolved, in: taskPath),
                !resolved.dropFirst(taskPath.count).split(separator: UInt8(ascii: "/")).contains(where: {
                    String(decoding: $0, as: UTF8.self).lowercased() == ".git"
                })
            else { throw CommandError.refused("A cache contains a link outside the copied folder.") }
        }
    }

    private static func forEachEntry(in descriptor: Int32, _ body: (String) throws -> Void) throws {
        let copy = dup(descriptor)
        guard copy >= 0 else { throw posixError() }
        guard let directory = fdopendir(copy) else { close(copy); throw posixError() }
        defer { closedir(directory) }
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 { throw posixError() }
                break
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8)
            }
            guard let name else { throw CommandError.refused("A cache contains an unsupported filename encoding.") }
            if name == "." || name == ".." { continue }
            guard isEntryName(name) else { throw CommandError.refused("A cache contains an invalid filename.") }
            try body(name)
        }
    }

    private static func removeEntry(_ name: String, in parent: Int32) {
        guard isEntryName(name) else { return }
        if let directory = try? openDirectory(name, at: parent) {
            defer { close(directory) }
            _ = fchmod(directory, 0o755)
            try? forEachEntry(in: directory) { removeEntry($0, in: directory) }
            _ = unlinkat(parent, name, AT_REMOVEDIR)
        } else {
            _ = unlinkat(parent, name, 0)
        }
    }

    private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    #endif
}
#endif
