#if DEBUG
import ACP
import SwiftUI

/// Inert models for the canvas and isolated UI checks. No processes or filesystem writes.
enum HomeNextPreviewFixtures {
    enum State: String {
        case busy, quiet, first, empty, loading, recovery, narrow
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
        let app = AppModel.preview(.empty)
        guard state != .first else { return app }
        let project = app.projects.add(URL(filePath: "/tmp/native-home-fixture", directoryHint: .isDirectory))
        app.focusProject(project.id)
        let titles = [
            "Fix flaky PermissionRequestTests", "AVIF thumbnails for the gallery",
            "Split DesignSystem into a package", "Move the host socket into Application Support",
            "Regenerate the schema types", "Queue follow-ups while a turn runs",
            "Dark mode for the marketing site", "Wrap diff lines at word boundaries",
            "Add setup steps to the README", "Compress originals before upload",
        ]
        let count = state == .quiet ? 10 : (state == .empty || state == .loading) ? 0 : state == .recovery ? 1 : 5
        for index in 0..<count {
            let title =
                state == .narrow && index == 0
                ? "Fix flaky PermissionRequestTests when approvals arrive while the host reconnects" : titles[index]
            let id = "home-next-\(index)"
            let date = Date.now.addingTimeInterval(-Double(52 - index * 8) * 60)
            app.catalog.add(
                SessionInfo(sessionId: SessionID(id), cwd: project.path, title: title, updatedAt: date),
                for: AgentDefinition.ID(rawValue: "codex"), in: project.id)
            guard let session = SessionModel.preview(in: app, agent: "codex", id: id, cwd: project.path, title: title)
            else { continue }
            if state == .quiet {
                session.previewExchange(
                    title, reply: "Done. The change is ready to review.", endedAgo: Double(index + 1) * 60)
            } else if state == .recovery {
                session.phase = .disconnected
            } else {
                session.previewRunningTurn(title)
                permission(
                    session,
                    command: index == 0
                        ? "swift test --filter PermissionRequestTests" : "swift test --filter TaskListTests",
                    date: date)
            }
        }
        return app
    }

    private static func permission(_ session: SessionModel, command: String, date: Date) {
        let json = """
            {"sessionId":"\(session.id.rawValue)","toolCall":{
            "toolCallId":"approval-\(session.id.rawValue)","title":"\(command)","kind":"execute",
            "status":"pending","rawInput":{"command":["/bin/zsh","-lc","\(command)"]}},
            "options":[{"optionId":"reject","name":"Don't Allow","kind":"reject_once"},
            {"optionId":"always","name":"Always Allow","kind":"allow_always"},
            {"optionId":"allow","name":"Allow","kind":"allow_once"}]}
            """
        guard let request = SessionModel.previewDecode(RequestPermissionRequest.self, json) else { return }
        session.state.apply(.toolCall(request.toolCall), at: date)
        session.state.requestPermission(request, id: .int(1))
    }

    static func page(_ state: State) -> some View {
        DSPreviewPair {
            HomeNextFixtureView(state: state)
                .environment(SettingsPresentation())
                .frame(width: state == .narrow ? DS.Size.popoverWidth : DS.HomeNext.column + DS.Space.xxxl * 2)
        }
    }
}

#endif
