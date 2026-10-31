#if os(macOS) || os(Linux)
import Foundation

#if os(macOS)
import Darwin
#endif

extension WorktreeClone {
    /// No byte-copy fallback: a large cache must never silently become a large duplicate.
    func perform(supportsClones check: ((URL, URL) -> Bool)? = nil) throws -> Report {
        var report = Report()
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let destination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard source != destination, !Self.contains(destination, in: source), !Self.contains(source, in: destination)
        else { throw CommandError.refused("Warm worktrees need separate project and worktree folders.") }
        #if os(macOS)
        guard (check ?? Self.supportsClones)(source, destination) else {
            report.unsupported = true
            return report
        }
        let sourceFD = try Self.openDirectory(source.path(percentEncoded: false))
        defer { close(sourceFD) }
        let destinationFD = try Self.openDirectory(destination.path(percentEncoded: false))
        defer { close(destinationFD) }
        for path in paths {
            try Task.checkCancellation()
            guard Self.validRelativePath(path) else {
                report.skipped.append(path)
                continue
            }
            let components = path.split(separator: "/").map(String.init)
            guard let name = components.last else { continue }
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
                    try Self.cloneEntry(
                        name, from: from, to: to, relative: name, projectPath: path,
                        project: sourceFD, task: destinationFD, created: &created)
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

    private static func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains {
                $0.isEmpty || $0 == "." || $0 == ".." || $0 == ".git"
            }
    }

    private static func contains(_ url: URL, in root: URL) -> Bool {
        url.pathComponents.starts(with: root.pathComponents)
    }

    #if os(macOS)
    private static func supportsClones(_ source: URL, _ destination: URL) -> Bool {
        var from = statfs()
        var to = statfs()
        guard statfs(source.path(percentEncoded: false), &from) == 0,
            statfs(destination.path(percentEncoded: false), &to) == 0
        else { return false }
        let apfs = withUnsafeBytes(of: from.f_fstypename) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self) == "apfs"
        }
        return apfs && from.f_fsid.val.0 == to.f_fsid.val.0 && from.f_fsid.val.1 == to.f_fsid.val.1
    }

    private static func openDirectory(_ path: String, at parent: Int32 = AT_FDCWD) throws -> Int32 {
        let descriptor = openat(parent, path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        return descriptor
    }

    private static func parentDirectory(_ root: Int32, components: ArraySlice<String>, create: Bool) throws -> Int32 {
        var descriptor = dup(root)
        guard descriptor >= 0 else { throw posixError() }
        do {
            for part in components {
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
        _ name: String, from source: Int32, to destination: Int32, relative: String, projectPath: String,
        project: Int32, task: Int32, created: inout Bool
    ) throws {
        try Task.checkCancellation()
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
                if child == ".git" {
                    // SwiftPM caches may contain standalone checkouts, but not Git redirects.
                    var metadata = stat()
                    guard fstatat(from, child, &metadata, AT_SYMLINK_NOFOLLOW) == 0,
                        metadata.st_mode & S_IFMT == S_IFDIR
                    else { throw CommandError.refused("A cached checkout uses an external git directory.") }
                    let gitDirectory = try openDirectory(child, at: from)
                    defer { close(gitDirectory) }
                    try validateGitMetadata(gitDirectory)
                }
                // Local env files are selected separately by Git after the user opts in.
                guard !child.hasPrefix(".env") else { return }
                var childCreated = false
                try cloneEntry(
                    child, from: from, to: to, relative: relative + "/" + child,
                    projectPath: projectPath + "/" + child, project: project, task: task, created: &childCreated)
            }
            guard fchmod(to, info.st_mode & 0o777) == 0 else { throw posixError() }
        case S_IFLNK:
            var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
            let count = readlinkat(source, name, &buffer, buffer.count)
            guard count > 0, count < buffer.count else { throw posixError() }
            let link = String(decoding: buffer.prefix(count), as: UTF8.self)
            guard
                isInternalCacheLink(link, relative: relative, projectPath: projectPath, project: project)
                    || isExistingProjectLink(link, at: projectPath, project: project, task: task)
            else {
                throw CommandError.refused("A cache contains a link outside the copied folder.")
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

    private static func isInternalCacheLink(
        _ link: String, relative: String, projectPath: String, project: Int32
    ) -> Bool {
        let relativeParts = relative.split(separator: "/").map(String.init)
        let projectParts = projectPath.split(separator: "/").map(String.init)
        let cacheParts = Array(projectParts.dropLast(relativeParts.count - 1))
        guard let cache = try? parentDirectory(project, components: cacheParts[...], create: false) else {
            return false
        }
        defer { close(cache) }
        return resolveLink(
            link, base: Array(relativeParts.dropFirst().dropLast()), root: cache, followLinks: true) != nil
    }

    private static func resolveLink(_ link: String, base: [String], root: Int32, followLinks: Bool) -> [String]? {
        guard !link.hasPrefix("/") else { return nil }
        var resolved = base
        var pending = link.split(separator: "/").map(String.init)
        var followed = 0
        while !pending.isEmpty {
            let part = pending.removeFirst()
            if part == "." { continue }
            if part == ".." {
                guard !resolved.isEmpty else { return nil }
                resolved.removeLast()
                continue
            }
            guard part != ".git",
                let parent = try? parentDirectory(root, components: resolved[...], create: false)
            else { return nil }
            defer { close(parent) }
            var info = stat()
            guard fstatat(parent, part, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
            if info.st_mode & S_IFMT == S_IFLNK {
                guard followLinks, followed < 40 else { return nil }
                followed += 1
                var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
                let count = readlinkat(parent, part, &buffer, buffer.count)
                guard count > 0, count < buffer.count else { return nil }
                let target = String(decoding: buffer.prefix(count), as: UTF8.self)
                guard !target.hasPrefix("/") else { return nil }
                // Expand links before processing subsequent '..' components, as the filesystem does.
                pending = target.split(separator: "/").map(String.init) + pending
                continue
            }
            guard
                info.st_mode & S_IFMT == S_IFDIR
                    || (pending.isEmpty && info.st_mode & S_IFMT == S_IFREG)
            else { return nil }
            resolved.append(part)
        }
        return resolved
    }

    private static func isExistingProjectLink(_ link: String, at path: String, project: Int32, task: Int32) -> Bool {
        let base = Array(path.split(separator: "/").map(String.init).dropLast())
        // Workspace targets must already exist in both checkouts without any link indirection.
        guard let target = resolveLink(link, base: base, root: project, followLinks: false), !target.isEmpty,
            resolveLink(link, base: base, root: task, followLinks: false) == target
        else { return false }
        return true
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
                String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            if name != ".", name != ".." { try body(name) }
        }
    }

    private static func removeEntry(_ name: String, in parent: Int32) {
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
