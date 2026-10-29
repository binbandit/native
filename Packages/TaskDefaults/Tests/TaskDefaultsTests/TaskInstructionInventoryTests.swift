import Foundation
import Testing

@testable import TaskDefaults

struct TaskInstructionInventoryTests {
    @Test func scopeOverrideFallbackAndMissingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-instructions-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appending(path: "project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("ordinary instructions".utf8).write(to: root.appending(path: "AGENTS.md"))
        try Data("override".utf8).write(to: project.appending(path: "AGENTS.override.md"))
        try Data("unused".utf8).write(to: project.appending(path: "AGENTS.md"))
        let locations: [TaskInstructionLocation] = [
            .init(scope: .user, directory: "not-used", environmentKey: "FIXTURE_AGENT_HOME", names: ["AGENTS.md"]),
            .init(scope: .project, names: ["AGENTS.override.md", "AGENTS.md"], firstExisting: true),
            .init(scope: .project, names: ["missing.md"]),
        ]
        let files = TaskInstructionInventory.read(
            locations, home: root, project: project, environment: ["FIXTURE_AGENT_HOME": root.path])
        #expect(files.count == 2)
        #expect(files.first?.scope == .user && files.first?.bytes == 21)
        #expect(files.last?.url.lastPathComponent == "AGENTS.override.md")
        #expect(TaskInstructionInventory.read(locations, home: root, project: nil, environment: [:]).isEmpty)
    }

    @Test func directoriesAreNotCountedAsInstructionFiles() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-instructions-\(UUID())")
        try FileManager.default.createDirectory(
            at: root.appending(path: "AGENTS.md"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            TaskInstructionInventory.read(
                [.init(scope: .project, names: ["AGENTS.md"])], home: root, project: root, environment: [:]
            ).isEmpty)
    }
}
