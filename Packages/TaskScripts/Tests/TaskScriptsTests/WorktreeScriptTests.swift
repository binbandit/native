import Foundation
import TaskScripts
import Testing

struct WorktreeScriptTests {
    @Test(arguments: [TaskScriptEvent.beforeWorktree, .afterWorktree])
    func worktreeCommandsKeepPolicyTrustAndProjectSettings(_ event: TaskScriptEvent) throws {
        let project = URL(filePath: "/work/project")
        var configuration = TaskScriptConfiguration(global: [event: "global"])
        configuration.updateProject(at: project) { $0.scripts[event] = "project" }
        let restored = try JSONDecoder().decode(TaskScriptConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(restored.plan(for: event, project: project).scripts.map(\.text) == ["global", "project"])
        let untrusted = restored.plan(for: event, project: project, repository: [event: "repository"])
        #expect(untrusted.scripts.map(\.text) == ["global"])
        #expect(untrusted.awaitingApproval?.text == "repository")
        #expect(
            restored.plan(
                for: event, project: project, repository: [event: "repository"],
                permissions: .init(userScripts: false, repositoryScripts: false)
            ).isEmpty)
        #expect(!event.holdsTask)
        #expect(TaskScriptEvent.setup.holdsTask)
    }
}
