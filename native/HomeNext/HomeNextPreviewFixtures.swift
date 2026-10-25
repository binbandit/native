#if DEBUG
import ACP
import Experiments
import GitHub
import NativeHostProtocol
import SwiftUI

/// Inert models for the canvas and isolated UI checks. No processes or filesystem writes.
enum HomeNextPreviewFixtures {
    enum State: String {
        case busy, calm, managed, quiet, first, empty, loading, recovery, narrow
        /// Busy, with every summary on: review requests, a usage limit and while you were away.
        case summaries
        /// Busy, with a draft in the start field, and with an address that can't start.
        case typed, startFailure
        case destructive, unknown, approvalFailure
        case question, questionText, questions, questionFailure, plan, planFailure, planText, planRetained, failure,
            failurePaused
    }

    static var requested: State? {
        UserDefaults.standard.string(forKey: "nativeHomeNextFixture").flatMap(State.init(rawValue:))
    }

    static let agents: [HomeAgent<AgentDefinition.ID>] = [
        HomeAgent(id: .init(rawValue: "claude-code"), name: "Claude Code", symbolName: "sparkle"),
        HomeAgent(id: .init(rawValue: "codex"), name: "Codex", symbolName: "terminal"),
        HomeAgent(
            id: .init(rawValue: "cursor"), name: "Cursor", symbolName: "cursorarrow",
            availability: .unavailable("Not installed")),
    ]

    static func model(_ state: State) -> AppModel {
        let defaults = PreviewUserDefaults()
        let app = AppModel(
            plugins: PluginRegistry(
                builtIns: [BuiltInPlugins.claudeCode, BuiltInPlugins.codex, BuiltInPlugins.cursor], defaults: defaults),
            defaults: defaults, catalogURL: nil,
            experiments: ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage()))
        app.experiments.set(true, for: .homeNext)
        _ = app.runtimes.sync()
        guard state != .first else { return app }
        let project = app.projects.add(URL(filePath: "/tmp/native-home-fixture/native", directoryHint: .isDirectory))
        app.focusProject(project.id)
        let titles = [
            "Fix flaky PermissionRequestTests", "AVIF thumbnails for the gallery",
            "Split DesignSystem into a package", "Move the host socket into Application Support",
            "Regenerate the schema types", "Queue follow-ups while a turn runs",
            "Dark mode for the marketing site", "Wrap diff lines at word boundaries",
            "Add setup steps to the README", "Compress originals before upload",
        ]
        let count =
            state == .quiet
            ? 10
            : (state == .empty || state == .loading)
                ? 0
                : state == .recovery ? 1 : (state == .calm || state == .managed) ? 7 : 5
        for index in 0..<count {
            let titleIndex: Int
            switch fixtureKind(state, index: index) {
            case .question, .questionText, .questions, .questionFailure: titleIndex = 1
            case .plan, .planFailure, .planText, .planRetained: titleIndex = 2
            case .failure, .failurePaused: titleIndex = 3
            default: titleIndex = index
            }
            let title =
                state == .narrow && index == 0
                ? "Fix flaky PermissionRequestTests when approvals arrive while the host reconnects"
                : titles[titleIndex]
            let kind = fixtureKind(state, index: index)
            let agent =
                [
                    State.question, .questionText, .questions, .questionFailure, .plan, .planFailure, .planText,
                    .planRetained,
                ].contains(
                    kind)
                ? "claude-code" : "codex"
            let id = "home-next-\(index)"
            let date = Date.now.addingTimeInterval(-Double(52 - index * 8) * 60)
            app.catalog.add(
                SessionInfo(sessionId: SessionID(id), cwd: project.path, title: title, updatedAt: date),
                for: AgentDefinition.ID(rawValue: agent), in: project.id)
            guard
                let session = fixtureSession(
                    in: app, agent: agent, id: id, cwd: project.path, title: title,
                    failsAnswer: kind == .questionFailure
                        || ([.approvalFailure, .planFailure].contains(state) && index == 0))
            else { continue }
            if state == .quiet {
                session.previewExchange(
                    title, reply: "Done. The change is ready to review.", endedAgo: Double(index + 1) * 60)
            } else if state == .recovery {
                session.phase = .disconnected
            } else {
                session.previewRunningTurn(title)
                switch kind {
                case .question, .questionText, .questions, .questionFailure:
                    question(session, kind: kind)
                case .plan, .planFailure, .planText, .planRetained:
                    plan(session, includesSteps: kind != .planText, date: date, retainsOlderPlan: kind == .planRetained)
                case .failure:
                    session.state.endTurn(.error)
                    session.state.apply(
                        .userMessageChunk(ContentChunk(content: .text(RecoveryPrompt(reason: .agentStopped).text))))
                    session.state.appendNotice("Codex exited (signal 9) while the build was linking.", isError: true)
                    session.state.endTurn(.error)
                    session.phase = .idle
                    session.lastStopReason = .error
                case .failurePaused:
                    var mirror = SessionMirror()
                    mirror.state = session.state
                    mirror.apply(
                        HostEvent(
                            seq: 1,
                            payload: .recovered(
                                RecoveryNote(
                                    cause: .agentStopped, action: .paused, agentName: "Codex", interruptedAt: date))))
                    session.state = mirror.state
                    session.phase = .idle
                    session.lastStopReason = .error
                case .quiet:
                    break
                default:
                    let command =
                        state == .destructive
                        ? "git push --force origin main"
                        : state == .unknown
                            ? "internal-check --workspace ."
                            : "swift test --package-path Packages/ACP --filter PermissionRequestTests"
                    permission(session, command: command, date: date, always: state != .managed)
                }
                session.lastActivity = date
            }
        }
        summaries(state, in: app)
        return app
    }

    /// Each summary shows only when the user turns it on (`summaryDefaults`); these are its data.
    private static func summaries(_ state: State, in app: AppModel) {
        switch state {
        case .summaries:
            let stopped = SessionKey(agent: .init(rawValue: "codex"), id: SessionID("home-next-4"))
            app.homeNext.fixtureLimits = [
                HomeNextLimit(
                    agent: .init(rawValue: "claude-code"), agentName: "Claude Code", window: "5-hour",
                    resetsAt: .now.addingTimeInterval(41 * 60), since: .now.addingTimeInterval(-42 * 60),
                    tasks: [stopped], titles: ["Regenerate the schema types"], resumes: true)
            ]
            app.homeNext.away = HomeNextAway(
                start: .now.addingTimeInterval(-138 * 60), end: .now.addingTimeInterval(-2 * 60), finished: 2,
                asked: 3, failed: 1)
        case .typed:
            app.quickEntry.draft = "Add a retry button to the failed upload toast, and cover it with a UI test"
        case .startFailure:
            app.quickEntry.draft = "Add a retry button to the failed upload toast"
            app.quickEntry.failure = "The project folder is unavailable. Choose another project or restore the folder."
        default:
            break
        }
    }

    /// Defaults with the summaries on for `.summaries`, and every one off otherwise (the calm default).
    static func summaryDefaults(_ state: State) -> UserDefaults {
        let defaults = PreviewUserDefaults()
        for summary in HomeNextSummary.allCases {
            defaults.set(state == .summaries, forKey: summary.storageKey)
        }
        return defaults
    }

    /// Review requests as gh returns them, for `.summaries`.
    @MainActor static func gitHub(_ state: State) -> GitHubModel? {
        guard state == .summaries else { return nil }
        return GitHubModel.preview(
            inbox: PullRequestInbox(
                authored: [],
                reviewRequested: [
                    PullRequestPreviewFixtures.summary(
                        "binbandit/native", 61, "perf(transcript): reuse row heights while streaming",
                        branch: "row-heights", minutesAgo: 60, author: "tessaro"),
                    PullRequestPreviewFixtures.summary(
                        "binbandit/pier", 212, "fix(uploads): resume multipart after a 413", branch: "multipart",
                        minutesAgo: 300, author: "okafor"),
                ],
                assigned: [], fetchedAt: .now))
    }

    private static func fixtureSession(
        in app: AppModel, agent: String, id: String, cwd: String, title: String, failsAnswer: Bool
    ) -> SessionModel? {
        guard let definition = app.runtime(AgentDefinition.ID(rawValue: agent))?.agent,
            let input = FileHandle(forReadingAtPath: "/dev/null"),
            let output = failsAnswer
                ? FileHandle(forReadingAtPath: "/dev/null") : FileHandle(forWritingAtPath: "/dev/null")
        else { return nil }
        // Own both handles: another preview's teardown must not close this fixture's transport.
        // A read-only sink deliberately fails without starting a process or touching project data.
        let connection = ACPConnection(reading: input, writing: output) { _ in }
        let session = SessionModel(
            agent: definition, id: SessionID(id), cwd: URL(filePath: cwd), connection: connection,
            services: app.sessions.services, supportsSteering: false, phase: .idle, title: title)
        app.sessions.register(session)
        return session
    }

    private static func fixtureKind(_ state: State, index: Int) -> State {
        let sequence: [State] = [.busy, .question, .plan, .failure, .quiet]
        let start: Int
        switch state {
        case .question, .questionText, .questions, .questionFailure: start = 1
        case .plan, .planFailure, .planText, .planRetained: start = 2
        case .failure, .failurePaused: start = 3
        default: start = 0
        }
        if index == 0 && start > 0 { return state }
        return sequence[min(start + index, sequence.count - 1)]
    }

    private static func question(_ session: SessionModel, kind: State) {
        let schema: String
        if kind == .questions, let questionnaire = AgentQuestionnaire.preview {
            // The composer's multi-question fixture uses the same wire schema.
            let fields = questionnaire.questions.map { question in
                "\"\(question.key)\":{\"type\":\"string\",\"description\":\"\(question.prompt)\"}"
            }.joined(separator: ",")
            schema = "{\"type\":\"object\",\"properties\":{\(fields)}}"
        } else if kind == .questionText {
            schema = #"{"type":"object","properties":{"answer":{"type":"string"}}}"#
        } else {
            schema =
                #"{"type":"object","properties":{"size":{"type":"string","title":"Thumbnail sizes","oneOf":[{"const":"both","title":"1x and 2x","description":"Sharp on Retina screens. About 1.4 GB more storage at today's library size."},{"const":"single","title":"Only 1x","description":"Today's behavior. Thumbnails look soft on Retina screens."}]},"size_custom":{"type":"string"}}}"#
        }
        let json = """
            {"sessionId":"\(session.id.rawValue)","mode":"form","message":"Should thumbnails cover 2x sizes too, or only 1x?","requestedSchema":\(schema)}
            """
        guard let request = SessionModel.previewDecode(CreateElicitationRequest.self, json) else { return }
        session.requestQuestion(request, id: kind == .questionFailure ? .string("unavailable") : .int(2))
    }

    private static func plan(
        _ session: SessionModel, includesSteps: Bool, date: Date, retainsOlderPlan: Bool = false
    ) {
        if includesSteps {
            let steps = [
                "Create Packages/DesignSystem with one library target, and move Tokens, Fonts and Brand into it.",
                "Move Components, Patterns and Status, making the types features use public.",
                "Load Geist through Bundle.module, keeping the fallback to the system font.",
                "Point the app at the package and remove the moved files from native.xcodeproj.",
                "Keep the Gallery as a preview target, and move its fixtures into the package's tests.",
                "Build the Mac app and typecheck the shared views for iPadOS.",
                "Run the package tests and compare the Gallery in light and dark.",
            ]
            let entries = steps.compactMap { step -> PlanEntry? in
                guard
                    let data = try? JSONEncoder().encode(["content": step, "priority": "medium", "status": "pending"])
                else { return nil }
                return try? JSONDecoder().decode(PlanEntry.self, from: data)
            }
            session.state.apply(.plan(entries))
        }
        if retainsOlderPlan {
            session.state.endTurn(.endTurn)
            session.state.appendUserMessage("Review a different proposal")
        }
        let proposal =
            retainsOlderPlan
            ? "Keep DesignSystem in the app and only rename its token groups."
            : "Move the shared views into Packages/DesignSystem, then build both clients."
        let json = """
            {"sessionId":"\(session.id.rawValue)","toolCall":{
            "toolCallId":"plan-\(session.id.rawValue)","title":"Move DesignSystem into a package","kind":"switch_mode",
            "status":"pending","rawInput":{"plan":"\(proposal)"}},
            "options":[{"optionId":"revise","name":"Revise","kind":"reject_once"},
            {"optionId":"approve","name":"Approve Plan","kind":"allow_once"}]}
            """
        guard let request = SessionModel.previewDecode(RequestPermissionRequest.self, json) else { return }
        session.state.apply(.toolCall(request.toolCall), at: date)
        session.state.requestPermission(request, id: .int(3))
    }

    private static func permission(_ session: SessionModel, command: String, date: Date, always: Bool = true) {
        let persistent = always ? #"{"optionId":"always","name":"Always Allow","kind":"allow_always"},"# : ""
        let json = """
            {"sessionId":"\(session.id.rawValue)","toolCall":{
            "toolCallId":"approval-\(session.id.rawValue)","title":"\(command)","kind":"execute",
            "status":"pending","rawInput":{"command":["/bin/zsh","-lc","\(command)"]}},
            "options":[{"optionId":"reject","name":"Don't Allow","kind":"reject_once"},
            \(persistent)
            {"optionId":"allow","name":"Allow","kind":"allow_once"}]}
            """
        guard let request = SessionModel.previewDecode(RequestPermissionRequest.self, json) else { return }
        session.state.apply(.toolCall(request.toolCall), at: date)
        session.state.requestPermission(request, id: .int(1))
    }

    /// The start field alone: at rest, with a draft, and with an address that can't start.
    static func startField() -> some View {
        DSPreviewPair {
            VStack(spacing: DS.Space.xl) {
                ForEach([State.busy, .typed, .startFailure], id: \.self) { state in
                    HomeNextFixtureView(state: state, showsPage: false)
                }
            }
            .environment(SettingsPresentation())
            .frame(width: DS.HomeNext.column + DS.Space.xxl * 2)
        }
    }

    static func page(_ state: State, narrow: Bool = false) -> some View {
        DSPreviewPair {
            HomeNextFixtureView(state: state)
                .environment(SettingsPresentation())
                .frame(
                    width: (narrow || state == .narrow) ? DS.Size.popoverWidth : DS.HomeNext.column + DS.Space.xxxl * 2)
        }
    }
}

#endif
