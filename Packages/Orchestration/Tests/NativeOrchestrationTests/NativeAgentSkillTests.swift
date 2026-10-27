import Foundation
import NativeOrchestration
import Testing

#if os(macOS) || os(Linux)
import Exec
#endif

@Suite("Native skill installation")
struct NativeAgentSkillTests {
    #if os(macOS) || os(Linux)
    @Test("A shared skill invokes the host of its task after another channel updates it")
    func currentHost() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-skill-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stable = root.appending(path: "Native 'Stable' Host")
        let nightly = root.appending(path: "Native Nightly Host")
        for (file, label) in [(stable, "stable"), (nightly, "nightly")] {
            try Data(("#!/bin/sh\nprintf '%s\\n' '" + label + "' \"$@\"\n").utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let skill = root.appending(path: "native-app")
        try NativeAgentSkill.install(at: skill, cli: stable.path)
        let initial = try await LocalCommandRunner().run(
            Command(
                skill.appending(path: "scripts/native").path, ["list_agents"],
                environment: [:], timeout: .seconds(5)))
        #expect(initial.exitCode == 0)
        #expect(initial.output == "stable\naction\nlist_agents\n")
        try NativeAgentSkill.install(at: skill, cli: nightly.path)
        let result = try await LocalCommandRunner().run(
            Command(
                skill.appending(path: "scripts/native").path, ["list_agents"],
                environment: ["NATIVE_ACTION_CLI": stable.path], timeout: .seconds(5)))
        #expect(result.exitCode == 0)
        #expect(result.output == "stable\naction\nlist_agents\n")
    }
    #endif

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
