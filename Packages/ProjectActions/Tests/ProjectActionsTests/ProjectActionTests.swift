import Foundation
import Testing

@testable import ProjectActions

struct ProjectActionTests {
    @Test func repoFileReadsWhatItCanAndSaysWhatItSkipped() {
        let json = """
            {
              "version": 1,
              "actions": [
                { "name": "Test", "command": "bun run test", "icon": "checkmark.seal" },
                { "name": "Web", "command": "bun run dev", "directory": "apps/web", "relativeTo": "project" },
                { "name": "Install", "command": "bun install", "runIn": "background", "future": true },
                { "name": "Broken" },
                { "name": "Split", "command": "x", "runIn": "split" },
                { "name": "Test", "command": "cargo test" }
              ]
            }
            """
        let contents = ProjectActionFile.decode(Data(json.utf8))
        guard case .actions(let actions, let skipped) = contents else {
            Issue.record("Expected actions, got \(contents)")
            return
        }
        #expect(actions.map(\.name) == ["Test", "Web", "Install", "Test"])
        #expect(actions.allSatisfy { $0.id.isFromRepository })
        // Two entries with one name still have ids of their own.
        #expect(Set(actions.map(\.id)).count == 4)
        #expect(actions[1].directory == .init(base: .project, path: "apps/web"))
        #expect(actions[2].presentation == .background)
        #expect(skipped.count == 2)
        #expect(skipped.first?.hasPrefix("Action 4") == true)
    }

    @Test func repoFileThatIsNotJSON() {
        guard case .unreadable(let reason) = ProjectActionFile.decode(Data("{ actions: [".utf8)) else {
            Issue.record("Expected unreadable")
            return
        }
        #expect(reason.contains("isn't valid JSON"))
        guard case .unreadable = ProjectActionFile.decode(Data(#"{ "tasks": [] }"#.utf8)) else {
            Issue.record("Expected unreadable without an actions list")
            return
        }
    }

    @Test func repoFileOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "repo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ProjectActionFile.read(in: root) == .none)
        let actions = [
            ProjectAction(name: "Lint", command: "just lint", presentation: .background),
            ProjectAction(name: "Docs", command: "make docs", directory: .init(base: .project, path: "docs")),
        ]
        let file = root.appending(path: ProjectActionFile.path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProjectActionFile.encode(actions).write(to: file)
        let read = ProjectActionFile.read(in: root).actions
        #expect(read.map(\.name) == ["Lint", "Docs"])
        #expect(read.map(\.presentation) == [.background, .terminal])
        #expect(read[1].directory == actions[1].directory)
    }

    @Test func privateActionsRoundTrip() throws {
        let action = ProjectAction(
            name: "Dev", command: "bun run dev", icon: "play.circle", directory: .init(base: .worktree, path: "web"),
            presentation: .terminal)
        let decoded = try JSONDecoder().decode(ProjectAction.self, from: JSONEncoder().encode(action))
        #expect(decoded == action)
    }

    @Test func keysForShortcuts() {
        #expect(ProjectAction.key(forName: "Test") == "test")
        #expect(ProjectAction.key(forName: "Compose Up") == "composeUp")
        #expect(ProjectAction.key(forName: "db:migrate") == "dbMigrate")
        #expect(ProjectAction.key(forName: "🚀") == nil)
    }

    @Test func directoriesStayInsideTheirBase() {
        let worktree = URL(filePath: "/tmp/wt", directoryHint: .isDirectory)
        let project = URL(filePath: "/tmp/project", directoryHint: .isDirectory)
        let web = ProjectAction.Directory(base: .worktree, path: "./apps//web/")
        #expect(web.resolved(worktree: worktree, project: project).path(percentEncoded: false) == "/tmp/wt/apps/web/")
        let escape = ProjectAction.Directory(base: .project, path: "../../etc")
        #expect(escape.resolved(worktree: worktree, project: project) == project)
    }
}
