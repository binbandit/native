import Foundation
import Testing

@testable import NativeHost

@Suite("Where clients may reach on a host")
struct ProjectPathsTests {
    /// `<root>/project` holding `file` and `sub/`, and `<root>/outside/secret` beside it.
    private struct Folders {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "native-paths-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        var project: String { path("project") }
        var outside: String { path("outside") }

        init() throws {
            let files = FileManager.default
            try files.createDirectory(atPath: path("project/sub"), withIntermediateDirectories: true)
            try files.createDirectory(atPath: path("outside"), withIntermediateDirectories: true)
            try Data("inside".utf8).write(to: root.appending(path: "project/sub/file"))
            try Data("secret".utf8).write(to: root.appending(path: "outside/secret"))
        }

        /// Resolved, as `ProjectPaths` answers (the temporary folder is behind a link on macOS).
        func path(_ relative: String) -> String {
            let path = root.appending(path: relative).path(percentEncoded: false)
            return ProjectPaths.resolvedPath(path) ?? path
        }

        func link(_ relative: String, to destination: String) throws {
            try FileManager.default.createSymbolicLink(
                atPath: root.appending(path: relative).path(percentEncoded: false), withDestinationPath: destination)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test func resolvesLinksAndDotsBeforeDeciding() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try folders.link("project/escape", to: folders.outside)
        try folders.link("project/alias", to: folders.path("project/sub"))
        let paths = ProjectPaths(roots: [folders.project, "/does/not/exist", "relative"])
        #expect(paths.roots == [folders.project])

        #expect(try paths.resolve(folders.project) == folders.project)
        #expect(try paths.resolve(folders.project + "/./sub//file") == folders.path("project/sub/file"))
        #expect(try paths.resolve(folders.project + "/alias/file") == folders.path("project/sub/file"))
        for escape in [
            folders.outside, folders.project + "/..", folders.project + "/../outside/secret",
            folders.project + "/escape", folders.project + "/escape/secret", folders.project + "/sub/../../outside",
            folders.project + "-sibling",
        ] {
            #expect(throws: ProjectPaths.Refusal.outsideProjects(escape)) { try paths.resolve(escape) }
        }
        #expect(throws: ProjectPaths.Refusal.notAbsolute("project/sub")) { try paths.resolve("project/sub") }
    }

    @Test func pathsNotThereYetResolveThroughTheirFolder() throws {
        let folders = try Folders()
        defer { folders.remove() }
        try folders.link("project/dangling", to: folders.outside + "/not-yet")
        let paths = ProjectPaths(roots: [folders.project])
        #expect(try paths.resolve(folders.project + "/sub/new/file") == folders.project + "/sub/new/file")
        for refused in [
            // ".." past a missing folder, and a link whose target would be created outside.
            folders.project + "/missing/../../outside", folders.project + "/dangling",
            folders.project + "/dangling/file",
        ] {
            #expect(throws: ProjectPaths.Refusal.outsideProjects(refused)) { try paths.resolve(refused) }
        }
    }

    @Test func readsKnownFilesThroughSearchOnlyDirectories() throws {
        let folders = try Folders()
        defer { folders.remove() }
        let directory = folders.path("project/sub")
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: directory)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }
        let paths = ProjectPaths(roots: [folders.project])
        let checked = try paths.resolve(folders.project + "/sub/file")
        let handle = try ProjectPaths.openForReading(checked)
        defer { try? handle.close() }
        #expect(try handle.readToEnd() == Data("inside".utf8))
    }

    @Test func readingNeverFollowsALinkSwappedInAfterTheCheck() throws {
        let folders = try Folders()
        defer { folders.remove() }
        let paths = ProjectPaths(roots: [folders.project])
        let checked = try paths.resolve(folders.project + "/sub/file")
        let handle = try ProjectPaths.openForReading(checked)
        #expect(try handle.readToEnd() == Data("inside".utf8))

        // The folder becomes a link out of the project between the check and the read.
        try FileManager.default.removeItem(atPath: folders.path("project/sub"))
        try FileManager.default.createDirectory(atPath: folders.outside + "/sub", withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: URL(filePath: folders.outside + "/sub/file"))
        try folders.link("project/sub", to: folders.outside + "/sub")
        #expect(throws: POSIXError.self) { try ProjectPaths.openForReading(checked) }

        // A FIFO would block the read forever.
        let fifo = folders.project + "/fifo"
        #expect(mkfifo(fifo, 0o600) == 0)
        #expect(throws: POSIXError.self) { try ProjectPaths.openForReading(try paths.resolve(fifo)) }
    }
}
