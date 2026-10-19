import Foundation
import TaskScripts
import Testing

struct TaskScriptPlanTests {
    private let project = URL(filePath: "/work/app", directoryHint: .isDirectory)

    private func sources(_ plan: TaskScriptPlan) -> [TaskScript.Source] {
        plan.scripts.map(\.source)
    }

    @Test func runsTheGlobalScriptAlone() {
        let configuration = TaskScriptConfiguration(global: [.setup: "bun install"])
        let plan = configuration.plan(for: .setup, project: project)
        #expect(plan.scripts == [TaskScript(event: .setup, source: .global, text: "bun install")])
        #expect(plan.timeout == .seconds(600))
        #expect(configuration.plan(for: .turnFinished, project: project).isEmpty)
    }

    @Test func runsTheProjectsScriptAfterTheGlobalOneByDefault() {
        var configuration = TaskScriptConfiguration(global: [.setup: "global"])
        configuration.updateProject(at: project) { $0.scripts[.setup] = "project" }
        #expect(sources(configuration.plan(for: .setup, project: project)) == [.global, .project])
        // Other projects only get the global one.
        let other = URL(filePath: "/work/other", directoryHint: .isDirectory)
        #expect(sources(configuration.plan(for: .setup, project: other)) == [.global])
    }

    @Test func aProjectCanReplaceTheGlobalScriptOrTurnItOff() {
        var configuration = TaskScriptConfiguration(global: [.teardown: "global"])
        configuration.updateProject(at: project) {
            $0.scripts[.teardown] = "project"
            $0.combinations[.teardown] = .insteadOfGlobal
        }
        #expect(sources(configuration.plan(for: .teardown, project: project)) == [.project])
        // Instead of the global one, with nothing of its own: nothing runs.
        configuration.updateProject(at: project) { $0.scripts[.teardown] = nil }
        #expect(configuration.plan(for: .teardown, project: project).isEmpty)
    }

    @Test func theRepositorysScriptTakesThePlaceOfTheProjectsOwn() {
        var configuration = TaskScriptConfiguration(global: [.setup: "global"])
        configuration.updateProject(at: project) {
            $0.scripts[.setup] = "mine"
            $0.allowsRepositoryScripts = true
        }
        let plan = configuration.plan(for: .setup, project: project, repository: [.setup: "./bootstrap"])
        #expect(plan.scripts.map(\.text) == ["global", "./bootstrap"])
        #expect(sources(plan) == [.global, .repository])
        #expect(plan.awaitingApproval == nil)
    }

    /// Whoever commits to a repository shouldn't get to run code on a Mac that never agreed to it.
    @Test func theRepositorysScriptWaitsUntilTheProjectAllowsIt() {
        var configuration = TaskScriptConfiguration(global: [.setup: "global"])
        configuration.updateProject(at: project) { $0.scripts[.setup] = "mine" }
        let plan = configuration.plan(for: .setup, project: project, repository: [.setup: "./bootstrap"])
        #expect(sources(plan) == [.global])
        #expect(plan.awaitingApproval == TaskScript(event: .setup, source: .repository, text: "./bootstrap"))
    }

    @Test func followsWhatTheOrganizationAllows() {
        var configuration = TaskScriptConfiguration(global: [.setup: "global"])
        configuration.updateProject(at: project) {
            $0.scripts[.setup] = "mine"
            $0.allowsRepositoryScripts = true
        }
        let repository: [TaskScriptEvent: String] = [.setup: "./bootstrap"]
        let noUserScripts = TaskScriptPermissions(userScripts: false, repositoryScripts: true)
        #expect(
            sources(
                configuration.plan(for: .setup, project: project, repository: repository, permissions: noUserScripts))
                == [.repository])
        let noRepositoryScripts = TaskScriptPermissions(userScripts: true, repositoryScripts: false)
        #expect(
            sources(
                configuration.plan(
                    for: .setup, project: project, repository: repository, permissions: noRepositoryScripts))
                == [.global, .project])
        let none = TaskScriptPermissions(userScripts: false, repositoryScripts: false)
        #expect(configuration.plan(for: .setup, project: project, repository: repository, permissions: none).isEmpty)
    }

    @Test func blankScriptsDontRun() {
        var configuration = TaskScriptConfiguration(global: [.setup: "  \n"])
        configuration.updateProject(at: project) { $0.allowsRepositoryScripts = true }
        #expect(configuration.plan(for: .setup, project: project, repository: [.setup: "\n"]).isEmpty)
    }

    @Test func aFolderOutsideAnyProjectGetsTheGlobalScripts() {
        let configuration = TaskScriptConfiguration(global: [.taskStarted: "echo hi"])
        #expect(sources(configuration.plan(for: .taskStarted, project: nil)) == [.global])
    }

    @Test func projectsAreTheSameWhateverTheirPathsSpelling() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var configuration = TaskScriptConfiguration()
        configuration.updateProject(at: folder) { $0.scripts[.setup] = "make" }
        // The temporary folder is under /var, a link to /private/var.
        let resolved = folder.resolvingSymlinksInPath()
        #expect(configuration.project(at: resolved).scripts[.setup] == "make")
        #expect(
            configuration.project(at: URL(filePath: resolved.path(percentEncoded: false) + "/")).scripts[.setup]
                == "make")
    }

    @Test func forgetsAProjectOnceItsBackToDefaults() {
        var configuration = TaskScriptConfiguration()
        configuration.updateProject(at: project) { $0.scripts[.setup] = "make" }
        #expect(configuration.projects.count == 1)
        configuration.updateProject(at: project) { $0.scripts[.setup] = nil }
        #expect(configuration.projects.isEmpty)
    }

    @Test func timeoutsDefaultPerEventAndCanChange() {
        var configuration = TaskScriptConfiguration()
        #expect(configuration.timeout(for: .setup) == .seconds(600))
        #expect(configuration.timeout(for: .turnFinished) == .seconds(60))
        configuration.timeouts[.setup] = .seconds(1800)
        #expect(configuration.plan(for: .setup, project: nil).timeout == .seconds(1800))
    }

    @Test func storesAsJSONAndDropsEventsItDoesntKnow() throws {
        var configuration = TaskScriptConfiguration(
            global: [.setup: "a", .teardown: "b"], timeouts: [.setup: .seconds(120)])
        configuration.updateProject(at: project) {
            $0.scripts[.turnFinished] = "c"
            $0.combinations[.turnFinished] = .insteadOfGlobal
            $0.allowsRepositoryScripts = true
        }
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(TaskScriptConfiguration.self, from: data) == configuration)

        let future = Data(
            #"{"global":{"setup":"a","pre-push":"z"},"timeouts":{"setup":120,"pre-push":5},"projects":{"/work/app":{"scripts":{"pre-push":"y"},"combinations":{"setup":"somethingNew"}}}}"#
                .utf8)
        let read = try JSONDecoder().decode(TaskScriptConfiguration.self, from: future)
        #expect(read.global == [.setup: "a"])
        #expect(read.timeouts == [.setup: .seconds(120)])
        #expect(read.project(at: project) == ProjectTaskScripts())
    }
}
