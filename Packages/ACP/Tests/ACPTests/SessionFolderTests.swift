import Foundation
import Testing

@testable import ACP

/// Codex records a session started in `/tmp/x` under `/private/tmp/x` and lists it only for that
/// spelling, so a project opened as `/tmp/x` lost its sessions on relaunch.
struct SessionFolderTests {
    /// A real folder and a symlink to it, like `/tmp` and `/private/tmp`.
    private func linkedFolders() throws -> (real: String, link: String) {
        let base = FileManager.default.temporaryDirectory.appending(path: "SessionFolderTests-\(UUID().uuidString)")
        let real = base.appending(path: "real")
        let link = base.appending(path: "link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        return (real.path(percentEncoded: false), link.path(percentEncoded: false))
    }

    @Test func listingAsksForTheResolvedSpellingToo() throws {
        let folders = try linkedFolders()
        let paths = SessionFolder.listingPaths(for: folders.link)
        #expect(paths.first == folders.link)
        #expect(paths.count == 2)
        #expect(paths.last.map { SessionFolder.isSame($0, folders.real) } == true)
        #if os(macOS)
        #expect(paths.last?.hasPrefix("/private/") == true)
        #endif
    }

    #if os(macOS)
    @Test func tmpIsListedUnderPrivateTmp() {
        #expect(SessionFolder.listingPaths(for: "/tmp") == ["/tmp", "/private/tmp"])
    }
    #endif

    @Test func aResolvedPathIsListedOnce() throws {
        let folders = try linkedFolders()
        let resolved = try #require(SessionFolder.listingPaths(for: folders.link).last)
        #expect(SessionFolder.listingPaths(for: resolved) == [resolved])
    }

    @Test func bothSpellingsAreTheSameFolder() throws {
        let folders = try linkedFolders()
        #expect(SessionFolder.isSame(folders.link, folders.real))
        #expect(SessionFolder.isSame(folders.link + "/", folders.real))
        #expect(!SessionFolder.isSame(folders.link, folders.real + "-other"))
    }

    /// A removed worktree still compares by where it was.
    @Test func aMissingFolderComparesThroughItsExistingParent() throws {
        let folders = try linkedFolders()
        #expect(SessionFolder.isSame(folders.link + "/gone/deeper", folders.real + "/gone/deeper"))
        #if os(macOS)
        #expect(SessionFolder.isSame("/tmp/missing-\(#line)", "/private/tmp/missing-\(#line)"))
        #endif
    }

    @Test func containsAFolderInside() throws {
        let folders = try linkedFolders()
        #expect(SessionFolder.contains(folders.link, folders.real + "/sub"))
        #expect(SessionFolder.contains(folders.real, folders.link))
        #expect(!SessionFolder.contains(folders.real, folders.real + "-other/sub"))
    }
}
