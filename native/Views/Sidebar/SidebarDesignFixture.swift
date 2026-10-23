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

private struct SidebarDesignFixture: View {
    let scenario: String
    @State private var app: AppModel
    @State private var gitHub = GitHubAccountPreviewFixtures.model(.single)
    @State private var statusBar = StatusBarRegistry(defaults: PreviewUserDefaults())

    init(scenario: String) {
        self.scenario = scenario
        _app = State(initialValue: Self.makeApp(scenario))
    }

    var body: some View {
        if scenario == "undo-toast" {
            UndoToastPreviewGallery()
        } else if scenario == "signals" {
            TaskSignalPreview()
        } else {
            RootView()
                .environment(app)
                .environment(gitHub)
                .environment(statusBar)
                .environment(\.projectIconStore, SidebarPreviewFixtures.iconStore)
                .environment(\.taskSignalReducedMotion, scenario == "reduce-motion")
        }
    }

    private static func makeApp(_ scenario: String) -> AppModel {
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
        for (project, prefix, count) in [(project, "native", rows.count), (pier, "pier", 3), (kite, "kite", 3)] {
            app.ordering.restore(
                (0..<count).map { SessionKey(agent: agent, id: SessionID("\(prefix)-\($0)")) }, in: project.id)
        }
        let selection = SessionKey(
            agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID(scenario == "ask" ? "native-1" : "native-2"))
        app.selection = selection
        return app
    }

    private static func add(
        _ app: AppModel, project: Project, id: String, title: String, status: TaskStatus,
        detail: String? = nil, age: TimeInterval = 0
    ) {
        let agent = AgentDefinition.ID(rawValue: "codex")
        app.catalog.add(
            SessionInfo(sessionId: SessionID(id), cwd: project.path, title: title, updatedAt: .now),
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
                #"{"sessionId":"kite-1","mode":"form","message":"Use the repo's PR template, or keep the built-in body?","requestedSchema":{"type":"object","properties":{"answer":{"type":"string"}}}}"#
            if let question = SessionModel.previewDecode(CreateElicitationRequest.self, json) {
                session.questions = [.init(id: .int(1), request: question, requestedAt: .now.addingTimeInterval(-age))]
            }
        case .done:
            session.previewExchange(title, reply: "Done. The change is ready to review.")
            app.unread.set(SessionKey(agent: agent, id: session.id), unread: id != "native-2")
        case .failed: session.phase = .disconnected
        default: break
        }
    }
}

#Preview("All in view - Full window fixture") {
    // The fixture's list uses the same in-memory models as the full window launch path.
    DSPreviewPair { AllInViewPreviewList(app: AllInViewPreviewFixtures.manyTasks()) }
}
#endif
