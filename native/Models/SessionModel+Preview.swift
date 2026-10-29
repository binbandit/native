#if DEBUG
import ACP
import Foundation

/// Sessions for previews. Their connection reads and writes nothing (`/dev/null`, never started), so
/// no agent process runs and nothing a view does reaches one.
extension SessionModel {
    /// A session of `agent`, registered with `app` so views that look it up find it. Nil if the app
    /// has no such agent.
    @discardableResult
    static func preview(
        in app: AppModel, agent: String = "claude-code", id: String = UUID().uuidString,
        cwd: String = AppPreviewFixtures.nativeFolder, title: String? = nil, phase: Phase = .idle,
        supportsSteering: Bool = true, promptCapabilities: PromptCapabilities = PromptCapabilities(image: true),
        configOptions: [ConfigOption] = []
    ) -> SessionModel? {
        guard let definition = app.runtime(AgentDefinition.ID(rawValue: agent))?.agent else { return nil }
        let connection = ACPConnection(reading: .nullDevice, writing: .nullDevice) { _ in }
        let session = SessionModel(
            agent: definition, id: SessionID(id), cwd: URL(filePath: cwd, directoryHint: .isDirectory),
            connection: connection, services: app.sessions.services, supportsSteering: supportsSteering,
            promptCapabilities: promptCapabilities, phase: phase, title: title, configOptions: configOptions)
        app.sessions.register(session)
        return session
    }

    /// A finished exchange: the user's prompt and the agent's reply.
    func previewExchange(_ prompt: String, reply: String, endedAgo seconds: TimeInterval = 60) {
        let date = Date.now.addingTimeInterval(-seconds)
        state.appendUserMessage(prompt, at: date.addingTimeInterval(-45))
        state.apply(.agentMessageChunk(ContentChunk(content: .text(reply))), at: date)
        state.endTurn(.endTurn, at: date)
        lastStopReason = .endTurn
        lastActivity = date
    }

    /// A turn under way: the prompt, and the agent's plan so far.
    func previewRunningTurn(_ prompt: String, plan: [PlanEntry] = []) {
        state.appendUserMessage(prompt, at: .now.addingTimeInterval(-74))
        if !plan.isEmpty {
            state.apply(.plan(plan))
        }
        phase = .prompting
        lastActivity = .now.addingTimeInterval(-74)
    }

    /// The agent asks to run a shell command, as Codex's adapter asks.
    func previewPermissionRequest(
        command: String = "swift test --filter PermissionRequestTests", reason: String? = nil, at date: Date = .now
    ) {
        if let reason { state.apply(.agentMessageChunk(ContentChunk(content: .text(reason))), at: date) }
        let call = """
            {"toolCallId": "call_preview_\(UUID().uuidString.prefix(8))", "title": "\(command)", "kind": "execute",
             "status": "pending", "rawInput": {"command": ["/bin/zsh", "-lc", "\(command)"]}}
            """
        let request = """
            {"sessionId": "\(id.rawValue)", "toolCall": \(call), "options": [
              {"optionId": "approved", "name": "Yes", "kind": "allow_once"},
              {"optionId": "approved-for-session", "name": "Yes, and don't ask again this task", "kind": "allow_always"},
              {"optionId": "abort", "name": "No, and tell Codex what to do differently", "kind": "reject_once"}]}
            """
        guard let update = Self.previewDecode(ToolCallUpdate.self, call),
            let permission = Self.previewDecode(RequestPermissionRequest.self, request)
        else { return }
        state.apply(.toolCall(update))
        state.requestPermission(permission, id: .int(state.items.count), at: date)
    }

    /// How much of the context window the session has used.
    func previewUsage(used: Int, size: Int = 200_000) {
        guard let usage = Self.previewDecode(Usage.self, #"{"used": \#(used), "size": \#(size)}"#) else { return }
        state.apply(.usage(usage))
    }

    static func previewDecode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }
}
#endif
