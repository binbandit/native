import ACP
import Experiments
import Foundation
import NativeCommands
import NativeHostClient
import NativeHostProtocol
import SessionTools
import TaskList
import Testing

@testable import Native
@testable import NativeLink

@main
struct NoProjectTestRunner {
    static func main() async {
        let result: CInt = await Testing.__swiftPMEntryPoint()
        exit(result)
    }
}

@Suite(.serialized) @MainActor
struct NoProjectModelTests {
    private func fixture() async throws -> (URL, AppModel, NoProjectTestHost) {
        let scratch = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("no-project-model-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let host = NoProjectTestHost(idPrefix: "task-\(UUID())")
        let client = NativeHostClient(transport: host, clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "no-project-fixture", name: "Fixture",
            agents: [
                AgentManifest(id: "workspace-fake", name: "Fixture", command: "/usr/bin/true")
            ])
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(true, for: .homeNext)
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults,
            catalogURL: scratch.appendingPathComponent("catalog.json"),
            scratchRoot: scratch.appendingPathComponent("private", isDirectory: true), experiments: experiments,
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appendingPathComponent("hosts"))))
        app.connectHost(client: client)
        await app.followHost()
        _ = await app.checkForAgents()
        return (scratch, app, host)
    }

    @Test func startWithNoProjectUsesScratchAndAppearsInSidebarAndArchive() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(app.projects.all.isEmpty)
        let picker = NativeCommand.newTasks(model: app).first { $0.id == .sessionNewWithAgent }
        #expect(picker?.isAvailable(CommandContext()) == true)
        #expect(app.agentPickerOptions().contains { $0.choice != nil })
        #expect(app.canCreateSession(with: AgentDefinition.ID(rawValue: "workspace-fake")))
        await app.newSession(with: AgentDefinition.ID(rawValue: "workspace-fake"))
        let key = try #require(app.selection)
        let task = try #require(app.session(key))
        #expect(task.isProjectless)
        #expect(app.catalog.lookup(key)?.project == NoProjectLocation.id)
        #expect(app.scratchTasks.owns(task.cwd))
        #expect(app.projects.all.isEmpty)
        #expect(app.currentProject == nil)
        #expect(app.sessionList.map(\.id).contains(key))
        #expect(!app.isAddingProject)
        app.rename(key, to: "Draft a release checklist")
        await app.archiveSession(key)
        #expect(app.archivedTaskGroups.flatMap(\.tasks).map(\.id).contains(key))
        #expect(FileManager.default.fileExists(atPath: task.cwd.path))
        await app.unarchiveSession(key)
        #expect(app.sessionList.map(\.id).contains(key))
    }

    @Test func homeStartDoesNotRequireAFolder() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        app.prepareHomeNextStart()
        app.quickEntry.draft = "Reply ready."
        let starting = try #require(app.startHomeNextTask(open: true))
        #expect(starting.project == NoProjectLocation.id)
        for _ in 0..<200 where starting.openedSession == nil && starting.failure == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let key = try #require(starting.openedSession)
        #expect(app.session(key)?.isProjectless == true)
        #expect(app.projects.all.isEmpty)
    }

    @Test func quickEntryAndComposeStartWithoutAProject() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        app.experiments.set(true, for: .composeTask)
        app.showQuickEntry()
        app.quickEntry.draft = "Reply ready."
        let quick = try #require(app.startQuickEntryDraft(open: true, send: false, confirms: false))
        for _ in 0..<200 where quick.openedSession == nil && quick.failure == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let quickKey = try #require(quick.openedSession)
        #expect(app.session(quickKey)?.isProjectless == true)
        app.expandQuickEntry()
        app.composeTask.editor?.draft = "Another thought"
        app.startComposeTask()
        let compose = try #require(app.composeTask.starting)
        for _ in 0..<200 where compose.openedSession == nil && compose.failure == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let composeKey = try #require(compose.openedSession)
        #expect(app.session(composeKey)?.isProjectless == true)
        #expect(app.session(quickKey)?.cwd != app.session(composeKey)?.cwd)
        #expect(app.projects.all.isEmpty)
    }

    @Test func gitAndWorktreeActionsAreAbsentEvenWhenScratchHasAGitFolder() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        await app.newSession(with: AgentDefinition.ID(rawValue: "workspace-fake"))
        let task = try #require(app.selection.flatMap(app.session))
        try FileManager.default.createDirectory(
            at: task.cwd.appendingPathComponent(".git"), withIntermediateDirectories: false)
        let registry = SessionToolRegistry(defaults: PreviewUserDefaults())
        registry.register(SessionToolsPreviewFixtures.changes)
        let screen = SessionToolsScreenModel(registry: registry)
        screen.open(.changes)
        let layout = registry.layout(for: task, on: screen)
        #expect(!layout.facts.contains(.changes))
        #expect(!layout.side.contains(.changes))
        #expect(!layout.workbench.contains(.changes))
        #expect(!task.canChangeWorkspace)
        #expect(
            NativeCommand.composer(model: app).first { $0.id == .sessionChangeWorkspace }?
                .isAvailable(CommandContext(session: task)) == false)
    }

    @Test func movePreservesConversationAndDraftAndCopiesFilesOnlyOnRequest() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        await app.newSession(with: AgentDefinition.ID(rawValue: "workspace-fake"))
        let key = try #require(app.selection)
        let source = try #require(app.session(key))
        source.hasSubmittedPrompt = true
        source.draft = "Keep this unsent follow-up"
        app.rename(key, to: "A chosen title")
        app.ordering.pin(key)
        try Data("Task draft".utf8).write(to: source.cwd.appendingPathComponent("draft.md"))
        let project = scratch.appendingPathComponent("atlas", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("Existing project".utf8).write(to: project.appendingPathComponent("draft.md"))
        try await app.moveToProject(key, folder: project, copyFiles: true)
        let target = try #require(app.session(key))
        #expect(target.id == source.id)
        #expect(target.cwd == project)
        #expect(!target.isProjectless)
        #expect(target.draft == source.draft)
        #expect(app.titleOfSession(key) == "A chosen title")
        #expect(app.ordering.isPinned(key))
        #expect(app.catalog.lookup(key)?.project == app.projects.all.first?.id)
        #expect(
            try String(contentsOf: project.appendingPathComponent("draft.md"), encoding: .utf8) == "Existing project")
        let children = try FileManager.default.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)
        #expect(children.contains { $0.lastPathComponent.hasPrefix("Task Files ") })
        #expect(FileManager.default.fileExists(atPath: source.cwd.path))
        let route = try #require(app.taskActionRoute(for: key))
        try await app.deleteWorkspace(using: route)
        #expect(!FileManager.default.fileExists(atPath: source.cwd.path))
        #expect(FileManager.default.fileExists(atPath: project.path))
    }

    @Test func emptyTaskMovesWithoutLosingDraftOrCopyingFiles() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        await app.newSession(with: AgentDefinition.ID(rawValue: "workspace-fake"))
        let oldKey = try #require(app.selection)
        let source = try #require(app.session(oldKey))
        source.draft = "An unsent thought"
        let project = scratch.appendingPathComponent("atlas", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try await app.moveToProject(oldKey, folder: project, copyFiles: false)
        let key = try #require(app.selection)
        let target = try #require(app.session(key))
        #expect(target.draft == "An unsent thought")
        #expect(target.cwd == project)
        #expect(app.catalog.lookup(oldKey) == nil)
        #expect(app.scratchTasks.folder(for: NoProjectLocation.key(key)) == source.cwd)
        #expect(try FileManager.default.contentsOfDirectory(atPath: project.path).isEmpty)
    }

    @Test func clearingKeepsPrivateFilesWithTheCurrentConversation() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        await app.newSession(with: AgentDefinition.ID(rawValue: "workspace-fake"))
        let old = try #require(app.selection.flatMap(app.session))
        old.previewExchange("Draft a checklist", reply: "Ready.")
        let current = try await app.clearConversation(of: old)
        #expect(app.scratchTasks.folder(for: NoProjectLocation.key(current.key)) == old.cwd)
        #expect(app.scratchTasks.folder(for: NoProjectLocation.key(old.key)) == nil)
        let oldRoute = try #require(app.taskActionRoute(for: old.key))
        try await app.deleteWorkspace(using: oldRoute)
        #expect(FileManager.default.fileExists(atPath: current.cwd.path))
    }

    @Test func failedMoveRetainsPrivateFilesAndOriginalCatalog() async throws {
        let (scratch, app, host) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        await app.newSession(with: AgentDefinition.ID(rawValue: "workspace-fake"))
        let key = try #require(app.selection)
        let source = try #require(app.session(key))
        source.hasSubmittedPrompt = true
        source.draft = "Still here"
        let project = scratch.appendingPathComponent("atlas", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        await host.failProjectLoad()
        await #expect(throws: (any Error).self) { try await app.moveToProject(key, folder: project, copyFiles: false) }
        #expect(app.catalog.lookup(key)?.project == NoProjectLocation.id)
        #expect(app.session(key)?.draft == "Still here")
        #expect(FileManager.default.fileExists(atPath: source.cwd.path))
        #expect(app.projects.all.isEmpty)
    }

    @Test func deleteUndoKeepsFilesAndCommittedDeletionCleansOnlyOwnedFolder() async throws {
        let (scratch, app, _) = try await fixture()
        defer { try? FileManager.default.removeItem(at: scratch) }
        await app.newSession(with: AgentDefinition.ID(rawValue: "workspace-fake"))
        let key = try #require(app.selection)
        let task = try #require(app.session(key))
        app.deleteSession(key)
        #expect(FileManager.default.fileExists(atPath: task.cwd.path))
        app.cancelDeletion(of: key)
        #expect(app.sessionList.map(\.id).contains(key))
        app.deleteSession(key)
        try await Task.sleep(for: AppModel.deletionGracePeriod + .milliseconds(100))
        #expect(app.catalog.lookup(key) == nil)
        #expect(!FileManager.default.fileExists(atPath: task.cwd.path))
        #expect(FileManager.default.fileExists(atPath: scratch.path))
    }
}
