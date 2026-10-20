import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

/// Window › Durable Sessions, the Phase 1 preview (`docs/durability.md`): with background agents
/// off, the user can still turn a host on for this channel and run sessions in that window. It goes
/// away once background agents are on by default.
extension DurableHost {
    /// Per channel: every development build shares one defaults domain but has a host of its own, so
    /// turning one build's preview on mustn't register the others'.
    static let previewEnabledKey = "NativeHostEnabled.\(HostRegistration().location.channel)"

    /// Whether a host runs at all: for the main window's sessions, or for the preview.
    var isEnabled: Bool {
        HostSessions.isEnabled || isPreviewEnabled
    }

    /// The preview window's start: connects if its host is on, with the agents plugins provide.
    /// With background agents on, launch already connected and the main window has the sessions.
    func start(plugins definitions: [AgentDefinition]) async {
        guard !HostSessions.isEnabled else { return }
        agents = definitions.map(AgentSpec.init)
        await startPreview()
    }

    /// Turns the preview's host on or off for this channel.
    func setEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.previewEnabledKey)
        isPreviewEnabled = enabled
        guard !HostSessions.isEnabled else { return }
        if enabled {
            await startPreview()
        } else {
            await disconnect()
            do {
                try await registrar.unregister()
            } catch {
                errorMessage = "Couldn't unregister the host: \(error.localizedDescription)"
            }
            registration = .off
        }
    }

    func startPreview() async {
        guard isPreviewEnabled, client == nil else { return }
        do {
            try await registrar.register()
            registration = .enabled
        } catch {
            registration =
                registrar.status == .needsApproval ? .needsApproval : .failed(error.localizedDescription)
        }
        connectInBackground()
    }

    // MARK: - Sessions

    /// Starts a session and returns its id, attached and ready to show.
    func newSession(agent: String, cwd: URL) async -> HostSessionID? {
        var created: HostSessionID?
        await perform("start a session") { client in
            let summary = try await client.newSession(
                NewSessionParams(agentID: agent, cwd: cwd.path(percentEncoded: false)))
            self.upsert(summary)
            self.mirrors[summary.id] = SessionMirror()
            try await client.attach(summary.id)
            created = summary.id
        }
        return created
    }

    func attach(_ session: HostSessionID) async {
        guard mirrors[session] == nil else { return }
        mirrors[session] = SessionMirror()
        await perform("open the session") { client in
            self.upsert(try await client.attach(session))
        }
    }

    /// Sends a message; it queues if a turn is running. The request id makes a retry after a dropped
    /// connection safe.
    func send(_ text: String, to session: HostSessionID) async {
        let params = PromptParams(sessionID: session, text: text)
        await perform("send the message") { client in
            _ = try await client.prompt(params)
        }
    }

    func cancel(_ session: HostSessionID) async {
        await perform("stop the turn") { client in try await client.cancel(session) }
    }

    func choose(_ option: PermissionOption, forToolCall toolCall: String, in session: HostSessionID) async {
        await perform("answer the request") { client in
            try await client.respondPermission(
                RespondPermissionParams(sessionID: session, toolCallID: toolCall, optionID: option.optionId))
        }
    }

    /// Stops the host and every agent it runs.
    func stopHost() async {
        await perform("stop the host") { client in try await client.shutdownHost(stopAgents: true) }
    }

    // MARK: - Events

    func applyPreview(_ step: SessionMirror.Step, to session: HostSessionID) {
        mirrors[session]?.apply(step)
    }

    func closePreview(_ session: HostSessionID) {
        mirrors[session] = nil
    }

    func clearPreview() {
        mirrors = [:]
    }
}
