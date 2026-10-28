import Foundation
import Testing

@testable import ProjectNames

@Suite struct ProjectNamesTests {
    @Test func resolvesCustomNamesAndClearing() {
        #expect(ProjectName.normalized("  Work Native \n", folderName: "native") == "Work Native")
        #expect(ProjectName.normalized(" \n", folderName: "native") == nil)
        #expect(ProjectName.normalized("native", folderName: "native") == nil)
        #expect(ProjectName(url: URL(filePath: "/work/native"), customName: "Work").name == "Work")
        #expect(ProjectName(url: URL(filePath: "/work/native"), customName: "  ").name == "native")
    }

    @Test func distinguishesShortestParentSuffixes() {
        let names = ["/work/native", "/personal/native", "/work/sample"].map {
            ProjectName(url: URL(filePath: $0))
        }
        #expect(ProjectName.qualifiers(for: names) == ["work", "personal", nil])
        let nested = ["/work/apps/native", "/personal/apps/native", "/apps/native"].map {
            ProjectName(url: URL(filePath: $0))
        }
        #expect(ProjectName.qualifiers(for: nested) == ["work/apps", "personal/apps", "/apps"])
    }

    @Test func respectsCustomNamesAndHostBoundaries() {
        let url = URL(filePath: "/work/native")
        #expect(
            ProjectName.qualifiers(for: [
                ProjectName(url: url),
                ProjectName(url: URL(filePath: "/personal/native"), customName: "Personal"),
            ]) == [nil, nil])
        #expect(
            ProjectName.qualifiers(for: [
                ProjectName(url: url), ProjectName(url: URL(filePath: "/personal/native"), scope: "paired-host"),
            ]) == [nil, nil])
    }

    @Test @MainActor func persistsAfterReopeningMovingAndClearing() throws {
        let domain = "ProjectNamesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let scratch = FileManager.default.temporaryDirectory.appending(path: domain)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let original = scratch.appending(path: "native")
        let moved = scratch.appending(path: "moved")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        ProjectNameStore(defaults: defaults).rename(original, to: "My Native")
        #expect(ProjectNameStore(defaults: defaults).name(for: original) == "My Native")
        try FileManager.default.moveItem(at: original, to: moved)
        let reloaded = ProjectNameStore(defaults: defaults)
        #expect(reloaded.name(for: moved) == "My Native")
        reloaded.rename(moved, to: " ")
        #expect(ProjectNameStore(defaults: defaults).name(for: moved) == nil)
        #expect(ProjectNameStore(defaults: defaults).name(for: original) == nil)
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test @MainActor func replacementFolderDoesNotTakeAMovedFoldersName() throws {
        let domain = "ProjectNamesTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let scratch = FileManager.default.temporaryDirectory.appending(path: domain)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let original = scratch.appending(path: "native")
        let moved = scratch.appending(path: "moved")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let store = ProjectNameStore(defaults: defaults)
        store.rename(original, to: "Work Native")
        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        #expect(store.name(for: original) == nil)
        store.rename(original, to: nil)
        #expect(store.name(for: moved) == "Work Native")
    }

}
