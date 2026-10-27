import Foundation
import NativeOrchestration
import Testing

@Suite("Native skill installation")
struct NativeAgentSkillTests {
    @Test("Fresh installation, Native-owned update, and user edits are distinguished")
    func ownership() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-skill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "native-app")
        try NativeAgentSkill.install(at: destination, cli: "/a path/Native Host")
        #expect(
            try String(contentsOf: destination.appending(path: "scripts/native"), encoding: .utf8).contains(
                "'/a path/Native Host'"))
        try NativeAgentSkill.install(at: destination, cli: "/new/path")
        #expect(
            try String(contentsOf: destination.appending(path: "scripts/native"), encoding: .utf8).contains(
                "'/new/path'"))
        let file = destination.appending(path: "SKILL.md")
        try Data("my own skill".utf8).write(to: file)
        #expect(throws: (any Error).self) { try NativeAgentSkill.install(at: destination, cli: "/another/path") }
        #expect(try String(contentsOf: file, encoding: .utf8) == "my own skill")
    }

    @Test("A user-owned skill, extra user file, or symlink is never overwritten")
    func collisions() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-skill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "native-app")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = destination.appending(path: "SKILL.md")
        try Data("owned by user".utf8).write(to: file)
        #expect(throws: (any Error).self) { try NativeAgentSkill.install(at: destination, cli: "/cli") }
        #expect(try String(contentsOf: file, encoding: .utf8) == "owned by user")
        let managed = root.appending(path: "managed")
        try NativeAgentSkill.install(at: managed, cli: "/cli")
        try Data("notes".utf8).write(to: managed.appending(path: "notes.txt"))
        #expect(throws: (any Error).self) { try NativeAgentSkill.install(at: managed, cli: "/new") }
        let link = root.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: managed)
        #expect(throws: (any Error).self) { try NativeAgentSkill.install(at: link, cli: "/new") }
    }
}
