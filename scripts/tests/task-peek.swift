import ACP
import Experiments
import Foundation
import NativeCommands

@testable import Native

@main
@MainActor
private struct TaskPeekChecks {
    static func main() async throws {
        try await checkRecovery()
        try checkQuestionNavigation()
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
        let registry = CommandRegistry(defaults: PreviewUserDefaults())
        require(app.legacyAskShortcutEnabled(in: registry), "Default shortcut still serves legacy approvals")
        guard let shortcut = KeyShortcut("⌘Y") else { throw MissingFixture() }
        registry.assign(shortcut, to: .sessionNew, resolving: .replace)
        require(!app.legacyAskShortcutEnabled(in: registry), "Reassigned Command-Y cannot approve through a fallback")
        registry.reset(.taskAnswerOldestAsk)
        require(app.legacyAskShortcutEnabled(in: registry), "Restoring the default restores legacy approval ownership")
        let commands = NativeCommand.taskPeek(model: app)
        require(commands.allSatisfy { !$0.showsInSettings() }, "Disabled experiment hides its shortcut settings")
        app.peekTask(routine.key)
        await app.answerOldestTaskAsk()
        require(
            app.taskPeek.request == nil && routine.permissionRequests.count == 1, "Default gate blocks both actions")
        app.experiments.set(true, for: .sidebarNext)
        require(!app.legacyAskShortcutEnabled(in: registry), "Global task ask withdraws every legacy fallback")
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
            "PASS: gate, shortcut ownership, global routing, recovery drafts, question navigation, stale and late asks"
        )
    }

    static func checkRecovery() async throws {
        guard let script = UserDefaults.standard.string(forKey: "peekRecoveryAgent") else { throw MissingFixture() }
        let defaults = PreviewUserDefaults()
        let plugin = ManifestPlugin(
            manifest: PluginManifest(
                id: "peek-recovery", name: "Peek recovery fixture",
                agents: [
                    AgentManifest(id: "peek-recovery", name: "Fixture", command: "/usr/bin/python3", args: [script])
                ]))
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [plugin], defaults: defaults), defaults: defaults, catalogURL: nil,
            experiments: ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage()))
        app.experiments.set(true, for: .sidebarNext)
        _ = await app.checkForAgents()
        defer { app.stopAgents() }
        let folder = FileManager.default.temporaryDirectory.appending(path: "peek-recovery-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = app.projects.add(folder)
        let current = try session("current", in: app, project: project, agent: "peek-recovery")
        let failed = try session("failed", in: app, project: project, agent: "peek-recovery")
        let background = try session("background", in: app, project: project, agent: "peek-recovery")
        current.previewExchange("Current task", reply: "Done")
        failed.previewExchange("Failed task", reply: "Interrupted")
        failed.phase = .disconnected
        current.draft = "Keep this while another task restarts."
        background.draft = "Keep this until I reopen the background task."
        let attachment = PromptAttachment(
            url: folder.appending(path: "note.txt"), content: .text("fixture"), byteCount: 7)
        current.attachments = [attachment]
        app.selection = current.key
        app.taskPeek.request = .init(task: failed.key, ask: nil)
        await app.recoverPeekedTask(failed.key)
        guard let reopened = app.session(current.key) else { throw MissingFixture() }
        require(reopened !== current, "Recovery actually rebuilt the selected task")
        require(reopened.draft == current.draft, "Peek recovery preserves the current task's draft")
        require(reopened.attachments == [attachment], "Peek recovery preserves attachments")
        require(app.selection == current.key, "Peek recovery keeps the selected task")
        await app.loadSession(background.key)
        require(app.session(background.key)?.draft == background.draft, "Recovery retains drafts until a later reopen")
    }

    static func checkQuestionNavigation() throws {
        guard let questionnaire = AgentQuestionnaire.preview else { throw MissingFixture() }
        let question = questionnaire.questions[0]
        var answers = AgentQuestionnaireAnswers()
        answers.pick(question.options[1], in: question)
        let next = questionnaire.questions[1]
        answers.answerHighlightedOption(answers.initialHighlight(in: next), in: next)
        answers.answerHighlightedOption(answers.initialHighlight(in: question), in: question)
        require(
            answers.isPicked(question.options[1], in: question), "Returning to a question preserves its saved choice")
        answers.answerHighlightedOption(2, in: question)
        require(answers.isPicked(question.options[2], in: question), "An explicit new highlight can change the answer")
        answers.clear(question)
        answers.typed[AgentQuestionnaireAnswers.textKey(for: question)] = "Keep my typed answer"
        answers.answerHighlightedOption(0, in: question)
        require(!answers.isPicked(question.options[0], in: question), "A highlight cannot replace typed text")
    }

    static func session(
        _ id: String, in app: AppModel, project: Project, agent name: String = "codex"
    ) throws -> SessionModel {
        let agent = AgentDefinition.ID(rawValue: name)
        app.catalog.add(SessionInfo(sessionId: SessionID(id), cwd: project.path, title: id), for: agent, in: project.id)
        guard let session = SessionModel.preview(in: app, agent: name, id: id, cwd: project.path) else {
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
