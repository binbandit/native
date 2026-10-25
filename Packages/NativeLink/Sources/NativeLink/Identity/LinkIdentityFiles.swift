import Darwin
import Foundation

/// The host's Link directory for `LinkIdentityMigration`: opened component by component without
/// following symlinks and checked for trusted ownership. Every file operation is relative to that
/// descriptor, so swapping a path component can't redirect it. It reads the legacy key but never
/// writes a secret.
final class LinkIdentityFiles {
    static let legacyName = "identity.key"
    static let recordName = "identity-storage.json"
    private let directory: Int32

    init(directory url: URL) throws {
        let path = url.path(percentEncoded: false)
        guard url.isFileURL, path.hasPrefix("/"), !path.utf8.contains(0) else {
            throw LinkIdentityStorageFailure.unsafePath
        }
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(".."), !components.contains(".") else {
            throw LinkIdentityStorageFailure.unsafePath
        }
        var current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { throw LinkIdentityStorageFailure.unsafePath }
        do {
            for (index, component) in components.enumerated() {
                let isLeaf = index == components.count - 1
                var next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0, errno == ENOENT, isLeaf {
                    guard mkdirat(current, component, 0o700) == 0 || errno == EEXIST else {
                        throw LinkIdentityStorageFailure.unsafePath
                    }
                    next = openat(current, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw LinkIdentityStorageFailure.unsafePath }
                close(current)
                current = next
                var info = stat()
                guard fstat(current, &info) == 0,
                    info.st_uid == geteuid() || (!isLeaf && info.st_uid == 0),
                    isLeaf
                        ? info.st_mode & 0o077 == 0
                        : (info.st_mode & 0o022 == 0 || (info.st_uid == 0 && info.st_mode & S_ISVTX != 0))
                else { throw LinkIdentityStorageFailure.unsafePath }
            }
            directory = current
        } catch {
            close(current)
            throw error
        }
    }

    deinit { close(directory) }

    func read(_ name: String, limit: Int) throws -> Data? {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw LinkIdentityStorageFailure.unsafePath }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, Self.isPrivateFile(info), info.st_size <= limit else {
            throw LinkIdentityStorageFailure.unsafePath
        }
        var result = Data(count: Int(info.st_size))
        let count = result.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count == result.count else { throw LinkIdentityStorageFailure.unsafePath }
        // Detect growth instead of accepting a valid prefix of a corrupt file.
        var extra: UInt8 = 0
        guard Darwin.read(descriptor, &extra, 1) == 0 else { throw LinkIdentityStorageFailure.unsafePath }
        return result
    }

    func exists(_ name: String) throws -> Bool {
        var info = stat()
        if fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        guard errno == ENOENT else { throw LinkIdentityStorageFailure.unsafePath }
        return false
    }

    func writeRecord(_ data: Data) throws {
        let temporary = ".identity-storage-\(UUID().uuidString).tmp"
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw LinkIdentityStorageFailure.migrationWriteFailed }
        defer {
            close(descriptor)
            unlinkat(directory, temporary, 0)
        }
        let count = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        guard count == data.count, fsync(descriptor) == 0,
            renameat(directory, temporary, directory, Self.recordName) == 0, fsync(directory) == 0
        else { throw LinkIdentityStorageFailure.migrationWriteFailed }
    }

    func removeLegacy() throws {
        var info = stat()
        if fstatat(directory, Self.legacyName, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw LinkIdentityStorageFailure.legacyRemovalFailed }
        } else {
            guard Self.isPrivateFile(info), unlinkat(directory, Self.legacyName, 0) == 0 else {
                throw LinkIdentityStorageFailure.legacyRemovalFailed
            }
        }
        guard fsync(directory) == 0 else { throw LinkIdentityStorageFailure.legacyRemovalFailed }
    }

    private static func isPrivateFile(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_uid == geteuid()
            && info.st_mode & 0o077 == 0 && info.st_nlink == 1
    }
}
