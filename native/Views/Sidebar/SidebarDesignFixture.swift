import SwiftUI

extension View {
    /// An inert, isolated Debug scene for inspecting the real list with repeatable task states.
    @ViewBuilder func sidebarDesignFixture() -> some View {
        #if DEBUG
        if let scenario = UserDefaults.standard.string(forKey: "nativeSidebarFixture") {
            SidebarDesignFixture(scenario: scenario)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
import ACP
import TaskList

struct SidebarDesignFixture: View {
    let scenario: String
    @State private var app: AppModel
    @State private var gitHub = GitHubAccountPreviewFixtures.model(.single)
    @State private var statusBar = StatusBarRegistry(defaults: PreviewUserDefaults())

    init(scenario: String) {
        self.scenario = scenario
        _app = State(
            initialValue: Self.makeApp(
                scenario == "peek-plan" ? "plan" : scenario == "facts-details" ? "facts" : scenario))
    }

    var body: some View {
        if scenario == "undo-toast" {
            UndoToastPreviewGallery()
        } else if scenario == "signals" {
            TaskSignalPreview()
        } else if scenario == "facts-details" {
            AllInViewPreviewList(app: app, insights: AllInViewPreviewFixtures.factsInsights)
        } else {
            RootView(initialSidebarVisibility: scenario.hasPrefix("collapsed") ? .detailOnly : .all)
                .environment(app)
                .environment(gitHub)
                .environment(statusBar)
                .environment(\.projectIconStore, SidebarPreviewFixtures.iconStore)
                .environment(\.taskSignalReducedMotion, scenario == "reduce-motion")
                .task {
                    CommandRegistry.shared.register(NativeCommand.taskPeek(model: app))
                    if let state = TaskPeekPreviewFixtures.State(rawValue: String(scenario.dropFirst(5))),
                        scenario.hasPrefix("peek-")
                    {
                        app.taskPeek.request = TaskPeekPreviewFixtures.prepare(app, state: state)
                    }
                }
        }
    }

    static func makeApp(_ scenario: String) -> AppModel {
        let defaults = PreviewUserDefaults()
        defaults.set(["automation": false, "automations": false, "expeditions": false], forKey: "pluginChoices")
        let plugins = PluginRegistry(
            builtIns: [BuiltInPlugins.claudeCode, BuiltInPlugins.codex, BuiltInPlugins.cursor], defaults: defaults)
        let app = AppModel(plugins: plugins, defaults: defaults, catalogURL: nil)
        _ = app.runtimes.sync()
        guard scenario != "empty" else { return app }
        let project = app.projects.add(URL(filePath: "/fixture/native"))
        guard scenario != "empty-project" else {
            app.catalog.replace(AgentDefinition.ID(rawValue: "codex"), in: project.id, with: []) { _ in false }
            return app
        }
        let rows: [(String, TaskStatus, String?)] = [
            ("Queue follow-ups while a turn runs", .working, nil),
            ("Fix flaky `PermissionRequestTests`", .needsPermission, "swift test --filter PermissionRequestTests"),
            ("Wrap diff lines at word boundaries", .done, nil),
            ("Task titles from the first prompt", .done, nil),
            ("Squash the release notes on main", .needsPermission, "git push --force origin main"),
            ("Move the host socket into Application Support", .working, nil),
            ("Remove the legacy workspace store", .idle, nil),
        ]
        for (index, row) in rows.enumerated() {
            add(
                app, project: project, id: "native-\(index)", title: row.0, status: row.1, detail: row.2,
                age: index == 1 ? 720 : 240)
        }
        let pier = app.projects.add(URL(filePath: "/fixture/pier"))
        add(app, project: pier, id: "pier-0", title: "Retry uploads when the network drops", status: .working)
        add(app, project: pier, id: "pier-1", title: "Landing page hero", status: .failed)
        add(app, project: pier, id: "pier-2", title: "AVIF thumbnails for the gallery", status: .done)
        let kite = app.projects.add(URL(filePath: "/fixture/kite"))
        add(app, project: kite, id: "kite-0", title: "Land saves into one commit per scope", status: .working)
        add(
            app, project: kite, id: "kite-1", title: "`kt pr` reads the PR template", status: .needsInput,
            detail: "Use the repo's PR template, or keep the built-in body?", age: 360)
        add(app, project: kite, id: "kite-2", title: "Shell completions for fish", status: .done)
        if scenario == "plan" {
            add(
                app, project: project, id: "plan", title: "Review the authentication migration",
                status: .needsPlanReview,
                detail:
                    "Six steps across authentication routes, their tests and the migration guide for existing clients.")
        }
        let agent = AgentDefinition.ID(rawValue: "codex")
        if scenario == "trio" {
            for id in ["native-6", "pier-2"] {
                app.archivedSessions.set(SessionKey(agent: agent, id: SessionID(id)), archived: true)
            }
            // Exercise the real menu, progress and Retry without reading a checkout or GitHub.
            var hasFailed = false
            app.refreshProjectState = { _, _ in
                try? await Task.sleep(for: .seconds(3))
                defer { hasFailed = true }
                return hasFailed ? [] : ["The fixture host is offline. Reconnect, then Retry."]
            }
        }
        for (project, prefix, count) in [(project, "native", rows.count), (pier, "pier", 3), (kite, "kite", 3)] {
            app.ordering.restore(
                (0..<count).map { SessionKey(agent: agent, id: SessionID("\(prefix)-\($0)")) }, in: project.id)
        }
        if scenario.hasPrefix("fold") || scenario == "facts" || scenario == "home-fold" {
            addEarlierTasks(app, project: project, pier: pier, kite: kite)
        }
        if scenario == "facts" {
            for fact in TaskSidebarPreferences.Fact.allCases { app.sidebarPreferences.set(fact, shown: true) }
            app.ordering.pin(SessionKey(agent: agent, id: SessionID("native-2")))
        }
        let selection = SessionKey(
            agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID(scenario == "ask" ? "native-1" : "native-2"))
        app.selection = selection
        if scenario.hasPrefix("collapsed-") {
            for item in app.tasksNeedingAttention {
                let keep =
                    scenario == "collapsed-single" && item.id.id.rawValue == "native-1"
                    || scenario == "collapsed-failure" && item.ask == nil
                guard !keep, let session = app.session(item.id) else { continue }
                for call in session.permissionRequests { session.state.resolvePermission(toolCallID: call.id) }
                session.questions = []
                session.phase = .idle
            }
        }
        if scenario == "collapsed-many" {
            for index in 0..<16 {
                add(
                    app, project: project, id: "waiting-\(index)",
                    title: "Verify the authentication migration and every dependent package \(index + 1)",
                    status: .needsPermission, detail: "swift test --filter AuthenticationMigrationTests",
                    age: Double(index) * 60)
            }
        }
        if scenario == "collapsed-child" || scenario == "collapsed-home" {
            let key = SessionKey(agent: agent, id: SessionID("native-1"))
            if let parent = app.session(key) {
                let child = parent.addSubagent(SessionID("approval-child"))
                app.sessions.register(child)
                child.phase = .prompting
                child.previewPermissionRequest(command: "swift test --filter ChildApprovalTests")
            }
            app.session(selection)?.draft = "Keep this conversation draft."
            if scenario == "collapsed-home" { app.selection = nil }
        }
        if scenario == "home-fold" { app.selection = nil }
        return app
    }

    private static func addEarlierTasks(_ app: AppModel, project: Project, pier: Project, kite: Project) {
        let agent = AgentDefinition.ID(rawValue: "codex")
        for (project, id, title, days) in [
            (project, "native-7", "Keyboard map for the composer", 1),
            (project, "native-8", "Archive tasks with a swipe on iPad", 2),
            (pier, "pier-3", "Dark mode for the marketing pages", 1),
            (pier, "pier-4", "Regenerate the schema types", 6),
            (kite, "kite-3", "Explain `kt land --dry-run` output", 3),
            (kite, "kite-4", "Rename `kt go` to `kt start`", 8),
        ] {
            let date = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
            app.catalog.add(
                SessionInfo(sessionId: SessionID(id), cwd: project.path, title: title, updatedAt: date),
                for: agent, in: project.id)
            if let session = SessionModel.preview(in: app, agent: "codex", id: id, cwd: project.path, title: title) {
                session.previewExchange(title, reply: "Done.", endedAgo: Date.now.timeIntervalSince(date))
            }
        }
    }

    private static func add(
        _ app: AppModel, project: Project, id: String, title: String, status: TaskStatus,
        detail: String? = nil, age: TimeInterval = 0
    ) {
        let agent = AgentDefinition.ID(rawValue: "codex")
        app.catalog.add(
            SessionInfo(
                sessionId: SessionID(id), cwd: project.path, title: title,
                updatedAt: status == .done ? .now.addingTimeInterval(-1080) : .now),
            for: agent, in: project.id)
        guard let session = SessionModel.preview(in: app, agent: "codex", id: id, cwd: project.path, title: title)
        else { return }
        if status.needsAttention {
            session.state.appendUserMessage(title, at: .now.addingTimeInterval(-age - 60))
            session.phase = .prompting
        }
        switch status {
        case .working: session.previewRunningTurn(title)
        case .needsPermission:
            session.previewPermissionRequest(command: detail ?? "swift test", at: .now.addingTimeInterval(-age))
        case .needsPlanReview:
            let request = RequestPermissionRequest(
                sessionId: session.id,
                toolCall: ToolCallUpdate(toolCallId: "plan", title: detail ?? "Review the plan", kind: .switchMode),
                options: [PermissionOption(optionId: "allow", name: "Approve", kind: .allowOnce)])
            session.state.requestPermission(request, id: .int(1))
        case .needsInput:
            let json =
                #"{"sessionId":"kite-1","mode":"form","message":"Should kt pr fill in the repo's PR template?","requestedSchema":{"type":"object","properties":{"answer":{"type":"string","oneOf":[{"const":"template","title":"Fill in the repo's template","description":"Summary and test plan go under its headings."},{"const":"builtin","title":"Keep the built-in body","description":"Ignore the template."},{"const":"fallback","title":"Use the template when one exists","description":"Fall back to the built-in body otherwise."}]}}}}"#
            if let question = SessionModel.previewDecode(CreateElicitationRequest.self, json) {
                session.questions = [.init(id: .int(1), request: question, requestedAt: .now.addingTimeInterval(-age))]
            }
        case .done:
            let date = Date.now.addingTimeInterval(-1080)
            session.state.appendUserMessage(title, at: date.addingTimeInterval(-45))
            let edit =
                #"{"toolCallId":"fixture-edit","title":"Update word wrapping","kind":"edit","status":"completed","content":[{"type":"diff","path":"native/Views/DiffView.swift","oldText":"let wraps = false","newText":"let wraps = true\nlet mode = WrapMode.words"}]}"#
            if let update = SessionModel.previewDecode(ToolCallUpdate.self, edit) {
                session.state.apply(.toolCall(update), at: date)
            }
            session.state.apply(
                .agentMessageChunk(ContentChunk(content: .text("Done. The change is ready to review."))), at: date)
            session.state.endTurn(.endTurn, at: date)
            session.lastStopReason = .endTurn
            session.lastActivity = date
            app.unread.set(SessionKey(agent: agent, id: session.id), unread: id != "native-2")
        case .failed:
            session.phase = .disconnected
            session.addNotice(
                "The provider was overloaded. Native tried to reconnect, but the agent stopped again.", isError: true)
        default: break
        }
    }
}

#Preview("All in view - Full window fixture") {
    // The fixture's list uses the same in-memory models as the full window launch path.
    DSPreviewPair { AllInViewPreviewList(app: AllInViewPreviewFixtures.manyTasks()) }
}
#endif
