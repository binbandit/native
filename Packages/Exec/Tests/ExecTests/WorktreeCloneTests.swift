import Foundation
import Testing

@testable import Exec

@Suite struct WorktreeCloneTests {
    @Test func unsupportedVolumesNeverCopy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("dist/output", "compiled")
        let request = WorktreeClone(source: fixture.source, destination: fixture.destination, paths: ["dist"])
        let report = try request.perform(supportsClones: { _, _ in false })
        #expect(report.unsupported && report.cloned.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appending(path: "dist").path()))
    }

    #if os(macOS)
    @Test func clonesWithoutSharingWritesAndPreservesInternalLinks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("node_modules/pkg/index.js", "original")
        try fixture.write("node_modules/.env", "fixture credentials")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.source.appending(path: "node_modules/link").path(), withDestinationPath: "pkg")
        try FileManager.default.createDirectory(
            at: fixture.source.appending(path: "node_modules/.bin"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: fixture.source.appending(path: "node_modules/.bin/tool").path(),
            withDestinationPath: "../pkg/index.js")
        let report = try await fixture.clone(["node_modules"])
        #expect(report.cloned == ["node_modules"])
        #expect(
            !FileManager.default.fileExists(atPath: fixture.destination.appending(path: "node_modules/.env").path()))
        let copied = fixture.destination.appending(path: "node_modules/pkg/index.js")
        #expect(try String(contentsOf: copied, encoding: .utf8) == "original")
        try Data("changed".utf8).write(to: copied)
        #expect(
            try String(contentsOf: fixture.source.appending(path: "node_modules/pkg/index.js"), encoding: .utf8)
                == "original")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: fixture.destination.appending(path: "node_modules/link").path()) == "pkg")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: fixture.destination.appending(path: "node_modules/.bin/tool").path()) == "../pkg/index.js")
    }

    @Test func rejectsEscapesAndLeavesExistingFilesAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(".env", "fixture source")
        try fixture.write("redirect/file", "must stay inside the task")
        try Data("keep".utf8).write(to: fixture.destination.appending(path: ".env"))
        try FileManager.default.createSymbolicLink(
            atPath: fixture.source.appending(path: "external").path(), withDestinationPath: fixture.base.path())
        try FileManager.default.createSymbolicLink(
            atPath: fixture.destination.appending(path: "redirect").path(), withDestinationPath: fixture.base.path())
        let paths = ["../escape", "/tmp/escape", ".git/config", "external", "redirect/file", ".env"]
        let report = try await fixture.clone(paths)
        #expect(report.cloned.isEmpty)
        #expect(report.skipped == paths)
        #expect(try String(contentsOf: fixture.destination.appending(path: ".env"), encoding: .utf8) == "keep")
        #expect(!FileManager.default.fileExists(atPath: fixture.base.appending(path: "file").path()))
    }

    @Test func doesNotLeaveAPartialCacheWhenALinkEscapes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(".build/output", "cache")
        try FileManager.default.createSymbolicLink(
            atPath: fixture.source.appending(path: ".build/outside").path(), withDestinationPath: "../../")
        let report = try await fixture.clone([".build"])
        #expect(report.skipped == [".build"])
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appending(path: ".build").path()))
    }

    @Test func decodesRequestsThroughTheCommandRunner() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("dist/output", "compiled")
        let report = try await fixture.clone(["dist"])
        #expect(report.cloned == ["dist"])
    }

    @Test func preservesWorkspaceLinksOnlyWhenBothProjectTargetsAreSafe() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write("packages/shared/index.js", "tracked workspace")
        try fixture.write("node_modules/cache", "dependency cache")
        let target = fixture.destination.appending(path: "packages/shared")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("tracked workspace".utf8).write(to: target.appending(path: "index.js"))
        try FileManager.default.createSymbolicLink(
            atPath: fixture.source.appending(path: "node_modules/shared").path(),
            withDestinationPath: "../packages/shared")
        let report = try await fixture.clone(["node_modules"])
        #expect(report.cloned == ["node_modules"])
        #expect(
            try String(contentsOf: fixture.destination.appending(path: "node_modules/shared/index.js"), encoding: .utf8)
                == "tracked workspace")
        try FileManager.default.removeItem(at: fixture.destination.appending(path: "node_modules"))
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(atPath: target.path(), withDestinationPath: fixture.base.path())
        let unsafe = try await fixture.clone(["node_modules"])
        #expect(unsafe.cloned.isEmpty && unsafe.skipped == ["node_modules"])
        #expect(!FileManager.default.fileExists(atPath: fixture.destination.appending(path: "node_modules").path()))
    }

    @Test func preservesStandaloneCachedCheckoutsButRejectsGitdirRedirects() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(".build/checkouts/package/.git/HEAD", "ref: refs/heads/main")
        try fixture.write("dist/nested/.git", "gitdir: /outside/project")
        let report = try await fixture.clone([".build", "dist"])
        #expect(report.cloned == [".build"])
        #expect(report.skipped == ["dist"])
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.destination.appending(path: ".build/checkouts/package/.git/HEAD").path()))
    }
    #endif

    private struct Fixture {
        let base: URL
        let source: URL
        let destination: URL

        init() throws {
            base = FileManager.default.temporaryDirectory.appending(path: "native-warm-clone-\(UUID())")
                .resolvingSymlinksInPath()
            source = base.appending(path: "project")
            destination = base.appending(path: "task")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        func write(_ path: String, _ text: String) throws {
            let file = source.appending(path: path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }

        func clone(_ paths: [String]) async throws -> WorktreeClone.Report {
            let request = WorktreeClone(source: source, destination: destination, paths: paths)
            let result = try await LocalCommandRunner().run(
                request.command(environment: ProcessInfo.processInfo.environment))
            let report = try JSONDecoder().decode(WorktreeClone.Report.self, from: result.standardOutput)
            try #require(!report.unsupported, "These integration fixtures need an APFS temp volume.")
            return report
        }

        func remove() { try? FileManager.default.removeItem(at: base) }
    }
}
