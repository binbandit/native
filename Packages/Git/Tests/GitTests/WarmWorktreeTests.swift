import Foundation
import Testing

@testable import Git

@Suite struct WarmWorktreeTests {
    #if os(macOS)
    @Test func detectsNestedIgnoredCachesAndRequiresEnvConsent() async throws {
        let fixture = try await TestRepository.make()
        defer { fixture.remove() }
        try fixture.write(".gitignore", "node_modules/\n.build/\ndist/\n.env*\ncache/\n!public/.env\n")
        try fixture.write("dist/tracked.txt", "tracked")
        try await fixture.git("add", ".gitignore")
        try await fixture.git("add", "--force", "dist/tracked.txt")
        try await fixture.git("commit", "--quiet", "-m", "Ignore caches")
        try fixture.write("apps/web/node_modules/pkg/index.js", "cached")
        try fixture.write(".build/cache", "built")
        try fixture.write("dist/local.txt", "not a wholly ignored folder")
        try fixture.write(".env", "FIXTURE=1")
        try fixture.write("cache/outputs/file", "custom cache")
        try fixture.write("public/.env", "UNIGNORED_FIXTURE=1")
        try fixture.write("apps/web/.env.local", "FIXTURE=2")
        let repository = try await fixture.repository
        let location = fixture.folder.deletingLastPathComponent().appending(path: "tasks")
        let cold = try await repository.createWorktree(forTask: "Without env", in: location)
        let report = try await repository.warmWorktree(at: cold.path, settings: WorktreeWarmSettings())
        #expect(Set(report.cloned) == [".build", "apps/web/node_modules"])
        #expect(!FileManager.default.fileExists(atPath: cold.path.appending(path: ".env").path()))
        #expect(!FileManager.default.fileExists(atPath: cold.path.appending(path: "dist/local.txt").path()))
        let warm = try await repository.createWorktree(forTask: "With env", in: location)
        let env = try await repository.warmWorktree(
            at: warm.path,
            settings: WorktreeWarmSettings(folders: [".build", "cache/outputs"], includesEnvironmentFiles: true))
        #expect(Set(env.cloned) == [".build", "cache/outputs", ".env", "apps/web/.env.local", "public/.env"])
    }
    #endif

    @Test func refusesAnotherRepositoryAndHonorsDisabledSetup() async throws {
        let fixture = try await TestRepository.make()
        let other = try await TestRepository.make()
        defer { fixture.remove(); other.remove() }
        let repository = try await fixture.repository
        await #expect(throws: GitError.self) {
            try await repository.warmWorktree(at: other.folder, settings: WorktreeWarmSettings())
        }
        let report = try await repository.warmWorktree(at: other.folder, settings: WorktreeWarmSettings(enabled: false))
        #expect(report.cloned.isEmpty)
    }

    @Test func rejectsNonProjectFolderChoices() {
        for path in ["../cache", "/tmp/cache", ".git", "foo/.git", ".env", ".env.local", "node_modules/../src", ""] {
            #expect(!WorktreeWarmSettings.isValidFolder(path))
        }
        #expect(WorktreeWarmSettings.isValidFolder("apps/web/node_modules"))
    }
}
