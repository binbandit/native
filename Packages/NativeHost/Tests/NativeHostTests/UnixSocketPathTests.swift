import Foundation
import NativeHostProtocol
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct UnixSocketPathTests {
    @Test func missingPathBindsWithOwnerOnlyPermissions() throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent("host.sock").path
            let descriptor = try UnixSocket.listen(at: path)
            defer { _ = close(descriptor) }
            try expectSocket(at: path)
            let client = try UnixSocket.connect(to: path)
            #expect(close(client) == 0)
        }
    }

    @Test func staleSocketCanBeRebound() throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent("host.sock").path
            let stale = try UnixSocket.listen(at: path)
            #expect(close(stale) == 0)
            try expectSocket(at: path)
            let descriptor = try UnixSocket.listen(at: path)
            defer { _ = close(descriptor) }
            try expectSocket(at: path)
            let client = try UnixSocket.connect(to: path)
            #expect(close(client) == 0)
        }
    }

    @Test func regularFileIsPreserved() throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent("host.sock")
            let sentinel = Data("keep this file".utf8)
            try sentinel.write(to: path)
            let original = try entry(at: path.path)

            try expectRefusal(at: path.path)
            let preserved = try entry(at: path.path)
            #expect(preserved.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG))
            #expect(preserved.st_ino == original.st_ino)
            #expect((try? Data(contentsOf: path)) == sentinel)
        }
    }

    @Test func directoryIsPreserved() throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent("host.sock")
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
            let child = path.appendingPathComponent("sentinel")
            let sentinel = Data("keep this directory".utf8)
            try sentinel.write(to: child)
            let original = try entry(at: path.path)
            try expectRefusal(at: path.path)
            let preserved = try entry(at: path.path)
            #expect(preserved.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR))
            #expect(preserved.st_ino == original.st_ino)
            #expect(try Data(contentsOf: child) == sentinel)
        }
    }

    @Test(arguments: [false, true])
    func symlinkIsPreserved(dangling: Bool) throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent("host.sock")
            let target = directory.appendingPathComponent("target")
            let sentinel = Data("keep this target".utf8)
            if !dangling { try sentinel.write(to: target) }
            try FileManager.default.createSymbolicLink(atPath: path.path, withDestinationPath: target.path)
            let original = try entry(at: path.path)
            let originalTarget = dangling ? nil : try entry(at: target.path)
            try expectRefusal(at: path.path)
            let preserved = try entry(at: path.path)
            #expect(preserved.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK))
            #expect(preserved.st_ino == original.st_ino)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: path.path) == target.path)
            if let originalTarget {
                #expect(try entry(at: target.path).st_ino == originalTarget.st_ino)
                #expect(try Data(contentsOf: target) == sentinel)
            } else {
                #expect(!FileManager.default.fileExists(atPath: target.path))
            }
        }
    }

    @Test func overlongPathFailsBeforeMutation() throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent(String(repeating: "x", count: 108))
            let sentinel = Data("keep this long path".utf8)
            try sentinel.write(to: path)
            let original = try entry(at: path.path)
            do {
                let descriptor = try UnixSocket.listen(at: path.path)
                _ = close(descriptor)
                Issue.record("Expected an overlong path to be refused")
            } catch UnixSocket.Failure.pathTooLong(let refusedPath) {
                #expect(refusedPath == path.path)
            }
            #expect(try entry(at: path.path).st_ino == original.st_ino)
            #expect(try Data(contentsOf: path) == sentinel)
        }
    }

    @Test func symlinkToSocketIsPreserved() throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent("host.sock").path
            let target = directory.appendingPathComponent("target.sock").path
            let descriptor = try UnixSocket.listen(at: target)
            defer { _ = close(descriptor) }
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
            let originalTarget = try entry(at: target)
            try expectRefusal(at: path)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: path) == target)
            #expect(try entry(at: target).st_ino == originalTarget.st_ino)
            let client = try UnixSocket.connect(to: target)
            #expect(close(client) == 0)
        }
    }

    @Test(.enabled(if: geteuid() != 0))
    func unlinkFailureIsPropagated() throws {
        try withScratchDirectory { directory in
            let path = directory.appendingPathComponent("host.sock").path
            let descriptor = try UnixSocket.listen(at: path)
            #expect(close(descriptor) == 0)
            let original = try entry(at: path)
            #expect(chmod(directory.path, 0o500) == 0)
            defer { _ = chmod(directory.path, 0o700) }
            do {
                let unexpected = try UnixSocket.listen(at: path)
                _ = close(unexpected)
                Issue.record("Expected socket removal to fail")
            } catch UnixSocket.Failure.system(let call, let code) {
                #expect(call == "unlink \(path)")
                #expect(code == EACCES)
            }
            #expect(try entry(at: path).st_ino == original.st_ino)
            try expectSocket(at: path)
        }
    }

    @Test func inspectionFailureIsPropagated() throws {
        try withScratchDirectory { directory in
            let parent = directory.appendingPathComponent("file")
            let sentinel = Data("not a directory".utf8)
            try sentinel.write(to: parent)
            let path = parent.appendingPathComponent("host.sock").path
            do {
                let descriptor = try UnixSocket.listen(at: path)
                _ = close(descriptor)
                Issue.record("Expected path inspection to fail")
            } catch UnixSocket.Failure.system(let call, let code) {
                #expect(call == "lstat \(path)")
                #expect(code == ENOTDIR)
            }
            #expect(try Data(contentsOf: parent) == sentinel)
        }
    }

    private func expectRefusal(at path: String) throws {
        do {
            let descriptor = try UnixSocket.listen(at: path)
            _ = close(descriptor)
            Issue.record("Expected a non-socket entry to be refused")
        } catch UnixSocket.Failure.nonSocketPath(let refusedPath) {
            #expect(refusedPath == path)
        }
    }

    private func expectSocket(at path: String) throws {
        let socket = try entry(at: path)
        #expect(socket.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK))
        #expect(socket.st_mode & 0o777 == 0o600)
    }

    private func entry(at path: String) throws -> stat {
        var entry = stat()
        guard lstat(path, &entry) == 0 else {
            throw UnixSocket.Failure.system("lstat fixture", errno: errno)
        }
        return entry
    }

    private func withScratchDirectory(_ body: (URL) throws -> Void) throws {
        let directory = URL(fileURLWithPath: "/tmp/nsp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
