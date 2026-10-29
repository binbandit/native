import ACP
import Foundation
import NativeHostProtocol

// Sessions: starting and opening them, following their events, sending messages, and answering
// what their agents ask.
extension NativeHostClient {
    public func sessions() async throws -> [HostSessionSummary] {
        try await call(HostProtocol.Method.listSessions, EmptyMessage())
    }

    /// Starts a session. With `attach`, its events follow from the first (a session id is chosen
    /// here if `params` has none) and it's re-attached after a reconnect, like `attach(_:)`.
    public func newSession(_ params: NewSessionParams) async throws -> HostSessionSummary {
        var params = params
        guard params.attach else { return try await call(HostProtocol.Method.newSession, params) }
        let session = params.sessionID ?? HostSessionID()
        params.sessionID = session
        return try await following(session) { try await $0.call(HostProtocol.Method.newSession, params) }
    }

    /// Opens a session the agent has. With `attach`, the answer comes once the session exists and
    /// its replay streams in after it (see `OpenSessionParams.attach`).
    public func openSession(_ params: OpenSessionParams) async throws -> HostSessionSummary {
        var params = params
        guard params.attach else { return try await call(HostProtocol.Method.openSession, params) }
        let session = params.sessionID ?? HostSessionID()
        params.sessionID = session
        let summary: HostSessionSummary = try await following(session) {
            try await $0.call(HostProtocol.Method.openSession, params)
        }
        if summary.id != session {
            // The agent session was open already, under another id.
            attachments[summary.id] = attachments.removeValue(forKey: session) ?? nil
        }
        return summary
    }

    /// Follows a session: its log is replayed onto `events` before this returns, then live events
    /// follow. After a reconnect it's re-attached from where it left off.
    @discardableResult
    public func attach(_ session: HostSessionID) async throws -> HostSessionSummary {
        let seen = attachments[session] ?? nil
        attachments.updateValue(seen, forKey: session)
        let result: AttachResult = try await call(
            HostProtocol.Method.attach, AttachParams(sessionID: session, epoch: epoch, afterSeq: seen))
        return result.summary
    }

    public func detach(_ session: HostSessionID) async throws {
        attachments[session] = nil
        let _: EmptyMessage = try await call(HostProtocol.Method.detach, SessionParams(sessionID: session))
    }

    /// Sends a message, and sends it again with the same request id if the connection drops before
    /// the host answers, for up to `patience`. The host delivers each request id once, so retrying
    /// never sends a message twice.
    public func prompt(_ params: PromptParams, patience: Duration = .seconds(60)) async throws -> PromptDelivery {
        let deadline = ContinuousClock.now + patience
        while true {
            do {
                let result: PromptResult = try await call(HostProtocol.Method.prompt, params)
                return result.delivery
            } catch  where Self.isConnectionLoss(error) && ContinuousClock.now < deadline {
                // The state may still say connected for a moment after the connection dropped.
                try await Task.sleep(for: .milliseconds(100))
                while hostInfo == nil, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    public func cancel(_ session: HostSessionID) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.cancel, SessionParams(sessionID: session))
    }

    public func respondPermission(_ params: RespondPermissionParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.respondPermission, params)
    }

    public func respondQuestion(_ params: RespondQuestionParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.respondQuestion, params)
    }

    /// Runs a command such as `/context` without showing it, and returns the agent's reply.
    public func runHidden(_ params: RunHiddenParams) async throws -> String {
        let result: RunHiddenResult = try await call(HostProtocol.Method.runHidden, params)
        return result.output
    }

    public func setConfigOption(_ params: SetConfigOptionParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.setConfigOption, params)
    }

    public func updateQueued(_ params: QueueItemParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.updateQueued, params)
    }

    public func removeQueued(_ params: QueueItemParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.removeQueued, params)
    }

    public func restoreQueued(_ params: RestoreQueuedParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.restoreQueued, params)
    }

    public func moveQueued(_ params: MoveQueuedParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.moveQueued, params)
    }

    public func sendQueuedNow(_ params: QueueItemParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.sendQueuedNow, params)
    }

    /// Replaces the MCP servers the agent gets for a session at its next load.
    public func setMCPServers(_ params: SetMCPServersParams) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.setMCPServers, params)
    }

    /// Stops tracking a session (its history stays with the agent), and with `closeInAgent` frees it
    /// in the agent's process too.
    public func closeSession(_ session: HostSessionID, closeInAgent: Bool = false) async throws {
        attachments[session] = nil
        let _: EmptyMessage = try await call(
            HostProtocol.Method.closeSession, CloseSessionParams(sessionID: session, closeInAgent: closeInAgent))
    }

    /// Confirms agent closure before forgetting the session. Failures preserve attachments and
    /// the host record so callers can retain private files and retry safely.
    public func closeSessionConfirmed(_ session: HostSessionID) async throws {
        let _: EmptyMessage = try await call(
            HostProtocol.Method.closeSessionConfirmed, SessionParams(sessionID: session))
        attachments[session] = nil
    }

    /// Runs a request that attaches `session` as it goes: events count from the first, and a
    /// failure leaves the session unfollowed.
    func following<Result: Sendable>(
        _ session: HostSessionID, _ request: (isolated NativeHostClient) async throws -> Result
    ) async throws -> Result {
        let wasFollowing = attachments.keys.contains(session)
        if !wasFollowing {
            attachments.updateValue(nil, forKey: session)
        }
        do {
            return try await request(self)
        } catch {
            if !wasFollowing {
                attachments[session] = nil
            }
            throw error
        }
    }
}
