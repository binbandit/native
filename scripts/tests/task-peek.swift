import ACP
import Experiments
import Foundation

@testable import Native

@main
@MainActor
private struct TaskPeekChecks {
    static func main() async throws {
        let defaults = PreviewUserDefaults()
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.codex], defaults: defaults),
            defaults: defaults, catalogURL: nil,
            experiments: ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage()))
        _ = app.runtimes.sync()
        let project = app.projects.add(URL(filePath: "/fixture/peek"))
        let current = try session("current", in: app, project: project)
        let routine = try session("routine", in: app, project: project)
        let destructive = try session("destructive", in: app, project: project)
        routine.previewPermissionRequest(command: "swift test", at: .now.addingTimeInterval(-120))
        destructive.previewPermissionRequest(command: "git push --force origin main", at: .now)
        app.selection = current.key
        current.draft = "Keep this draft while another task needs me."

        require(!app.offersTaskPeek, "Peek is off by default")
        let commands = NativeCommand.taskPeek(model: app)
        require(commands.allSatisfy { !$0.showsInSettings() }, "Disabled experiment hides its shortcut settings")
        app.peekTask(routine.key)
        await app.answerOldestTaskAsk()
        require(
            app.taskPeek.request == nil && routine.permissionRequests.count == 1, "Default gate blocks both actions")
        app.experiments.set(true, for: .sidebarNext)
        require(commands.allSatisfy { $0.showsInSettings() }, "Enabled experiment exposes its shortcut settings")
        require(app.oldestTaskAsk?.task == routine.key, "Oldest ask is chosen across tasks")
        await app.answerOldestTaskAsk()
        require(routine.permissionRequests.isEmpty, "Routine shortcut answers the oldest ask")
        require(destructive.permissionRequests.count == 1, "Newer ask remains untouched")
        require(app.selection == current.key && !current.draft.isEmpty, "Global answer preserves selection and draft")
        await app.answerOldestTaskAsk()
        require(app.taskPeek.request?.task == destructive.key, "Destructive shortcut opens Peek")
        require(destructive.permissionRequests.count == 1, "Destructive shortcut sends no approval")

        let stale = try firstAsk(app, destructive.key)
        let option = try allow(stale)
        guard case .permission(let call) = stale.content else { throw MissingFixture() }
        destructive.state.resolvePermission(toolCallID: call.id)
        destructive.previewPermissionRequest(command: "swift build")
        await app.answerTaskAsk(stale, option: option)
        require(destructive.permissionRequests.count == 1, "Stale click cannot answer a successor")

        let child = current.addSubagent(SessionID("child"))
        app.sessions.register(child)
        child.previewPermissionRequest(command: "git status", at: .now.addingTimeInterval(-300))
        require(app.oldestTaskAsk?.task == current.key, "Child ask anchors to its parent row")
        require(app.oldestTaskAsk?.session === child, "Child ask keeps its responding session")
        await app.answerOldestTaskAsk()
        require(child.permissionRequests.isEmpty, "Child answer reaches the child")
        require(destructive.permissionRequests.count == 1, "Child answer leaves other asks intact")
        let disconnected = try firstAsk(app, destructive.key)
        destructive.phase = .disconnected
        require(app.oldestTaskAsk == nil, "Disconnected asks leave global routing")
        await app.answerTaskAsk(disconnected, option: try allow(disconnected))
        require(destructive.permissionRequests.count == 1, "Disconnected ask cannot be answered")
        destructive.phase = .idle

        // A task can finish loading, or receive a new ask, after its Peek was opened.
        app.taskPeek.request = .init(task: routine.key, ask: nil)
        routine.previewPermissionRequest(command: "swift test")
        let arrived = try firstAsk(app, routine.key)
        await app.answerTaskAsk(arrived, option: try allow(arrived))
        require(routine.permissionRequests.isEmpty, "Late permission is answered")
        require(app.taskPeek.request == nil, "Answer closes Peek when its ask arrived after opening")

        app.taskPeek.request = .init(task: routine.key, ask: nil)
        let question = try JSONDecoder().decode(
            CreateElicitationRequest.self,
            from: Data(
                #"{"sessionId":"routine","message":"Use the template?","mode":"form","requestedSchema":{"type":"object","properties":{}}}"#
                    .utf8))
        routine.requestQuestion(question, id: .int(99))
        let questionAsk = try firstAsk(app, routine.key)
        await app.answerTaskQuestion(questionAsk, content: [:])
        require(routine.pendingQuestion == nil, "Late question is answered")
        require(app.taskPeek.request == nil, "Answer closes a late question Peek")
        print(
            "PASS: default gate, oldest routing, draft preservation, destructive review, stale and child asks, late answers"
        )
    }

    static func session(_ id: String, in app: AppModel, project: Project) throws -> SessionModel {
        let agent = AgentDefinition.ID(rawValue: "codex")
        app.catalog.add(SessionInfo(sessionId: SessionID(id), cwd: project.path, title: id), for: agent, in: project.id)
        guard let session = SessionModel.preview(in: app, agent: "codex", id: id, cwd: project.path) else {
            throw MissingFixture()
        }
        return session
    }

    static func firstAsk(_ app: AppModel, _ key: SessionKey) throws -> TaskPeekAsk {
        guard let ask = app.taskAsks(for: key).first else { throw MissingFixture() }
        return ask
    }

    static func allow(_ ask: TaskPeekAsk) throws -> PermissionOption {
        guard case .permission(let call) = ask.content,
            let option = call.permission?.options.first(where: { $0.kind == .allowOnce })
        else { throw MissingFixture() }
        return option
    }

    static func require(_ condition: Bool, _ message: String) {
        guard condition else {
            print("FAIL: \(message)")
            exit(1)
        }
    }

    struct MissingFixture: Error {}
}
