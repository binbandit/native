import Foundation
import Testing

@testable import TaskList

@Suite @MainActor
struct TaskScratchStoreTests {
    private func fixture() throws -> (URL, TaskScratchStore) {
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("task-scratch-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        return (temporary, TaskScratchStore(root: temporary.appendingPathComponent("private", isDirectory: true)))
    }

    @Test func startsHavePrivateIndependentDirectoriesAndRetryReuses() throws {
        let (temporary, model) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = try model.create(for: "starting/one")
        let second = try model.create(for: "starting/two")
        #expect(first != second)
        #expect(first.deletingLastPathComponent() == model.root)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(try model.create(for: "starting/one") == first)
        let mode = try FileManager.default.attributesOfItem(atPath: first.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
        try model.transfer(from: "starting/one", to: "agent/task")
        #expect(model.folder(for: "starting/one") == nil)
        #expect(model.folder(for: "agent/task") == first)
        #expect(TaskScratchStore(root: model.root).folder(for: "agent/task") == first)
    }

    @Test func conversationReplacementRetainsOneOwner() throws {
        let (temporary, model) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let folder = try model.create(for: "agent/earlier")
        try model.reassign(folder, to: "agent/current")
        try model.delete("agent/earlier")
        #expect(FileManager.default.fileExists(atPath: folder.path))
        #expect(model.folder(for: "agent/current") == folder)
        try model.delete("agent/current")
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func undoAndArchiveKeepFilesUntilActualDeletion() throws {
        let (temporary, model) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let first = try model.create(for: "agent/one")
        let second = try model.create(for: "agent/two")
        let file = first.appendingPathComponent("draft.txt")
        try Data("Private draft".utf8).write(to: file)
        let reopened = TaskScratchStore(root: model.root)
        #expect(try Data(contentsOf: file) == Data("Private draft".utf8))
        try reopened.delete("agent/one")
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(reopened.folder(for: "agent/one") == nil)
    }

    @Test func moveCopiesWithoutOverwritesAndRetainsOriginals() throws {
        let (temporary, model) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let privateFolder = try model.create(for: "agent/task")
        let project = temporary.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("Original project".utf8).write(to: project.appendingPathComponent("notes.md"))
        try Data("Task notes".utf8).write(to: privateFolder.appendingPathComponent("notes.md"))
        let copied = try #require(try model.copyFiles(of: "agent/task", into: project))
        #expect(copied.deletingLastPathComponent() == project)
        #expect(
            try String(contentsOf: project.appendingPathComponent("notes.md"), encoding: .utf8) == "Original project")
        #expect(try String(contentsOf: copied.appendingPathComponent("notes.md"), encoding: .utf8) == "Task notes")
        #expect(FileManager.default.fileExists(atPath: privateFolder.path))
        try model.delete("agent/task")
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }

    @Test func failedCopyAndSymlinkedScratchNeverRemoveUserFiles() throws {
        let (temporary, model) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let folder = try model.create(for: "agent/task")
        #expect(throws: (any Error).self) {
            try model.copyFiles(of: "agent/task", into: temporary.appendingPathComponent("missing"))
        }
        let outside = temporary.appendingPathComponent("user-owned", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        #expect(throws: TaskScratchStore.Failure.self) { try model.delete("agent/task") }
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(model.folder(for: "agent/task") == folder)
    }

    @Test func emptyCopyDoesNotCreateClutterAndScratchCannotBecomeAProject() throws {
        let (temporary, model) = try fixture()
        defer { try? FileManager.default.removeItem(at: temporary) }
        let folder = try model.create(for: "agent/task")
        #expect(try model.copyFiles(of: "agent/task", into: temporary) == nil)
        #expect(throws: TaskScratchStore.Failure.self) { try model.copyFiles(of: "agent/task", into: folder) }
    }
}
