import ACP
import Foundation
import NativeHostProtocol

extension HostCore {
    /// Settings replies replace whole snapshots. Keep changes from every client in order for this
    /// session, including the durable choices, while other sessions continue independently.
    func setConfigOption(_ params: SetConfigOptionParams) async throws {
        let session = try session(params.sessionID)
        let previous = session.configChange?.task
        let id = UUID()
        let loadGeneration = session.loadGeneration
        let link = agents[session.record.agentID]
        let generation = link?.status == .ready ? link?.generation : nil
        let task = Task {
            _ = await previous?.result
            guard sessions[session.id] === session, session.loadGeneration == loadGeneration else {
                throw PeerError.closed
            }
            if let link, let generation {
                guard agents[session.record.agentID] === link, link.generation == generation else {
                    throw PeerError.closed
                }
            }
            try await applyConfigOption(params, to: session)
        }
        session.configChange = (id, task)
        publish(session)
        defer {
            if session.configChange?.id == id {
                session.configChange = nil
                if sessions[session.id] === session { publish(session) }
                exitIfIdleForRestart()
            }
        }
        try await task.value
    }

    private func applyConfigOption(_ params: SetConfigOptionParams, to session: HostSession) async throws {
        try require(agent: session.record.agentID)
        try await load(session)
        try require(agent: session.record.agentID)
        let changesPermissions =
            params.permissionMode != nil
            || session.mirror.state.configOptions.contains(where: { $0.id == params.configID && $0.category == "mode" })
        let changeID = UUID()
        if changesPermissions {
            try requirePermission(in: session, value: params.value, intent: params.permissionMode)
            session.pendingPermissionChanges[changeID] = (params.value, params.permissionMode)
        }
        defer { session.pendingPermissionChanges[changeID] = nil }
        guard let link = agents[session.record.agentID], let peer = link.peer,
            let agentSessionID = session.record.agentSessionID
        else { throw HostError.agentUnavailable(session.agentName) }
        let generation = link.generation
        let response = try await peer.request(
            "session/set_config_option",
            RawSetConfigOptionRequest(sessionId: agentSessionID, configId: params.configID, value: params.value),
            as: RawConfigOptionsResponse.self)
        guard sessions[session.id] === session, generation == link.generation, link.peer === peer,
            session.record.agentSessionID == agentSessionID
        else { throw PeerError.closed }
        if let options = response.configOptions {
            append(.update(SessionMirror.configOptionsUpdate(options)), to: session)
            pinConfig(Self.configOptions(options), of: session)
        } else {
            session.record.configChoices[params.configID] = params.value
            try store.updateSession(session.record)
        }
        // Both the policy and the provider's permission controls can change during the RPC.
        endDeniedAgentWork()
        if changesPermissions {
            try requirePermission(in: session, value: params.value, intent: params.permissionMode)
        }
        // Check the actual provider response against the replacement intent, even when two
        // shared modes use the same provider control and pinConfig retained the previous intent.
        try requirePermission(in: session, intent: params.permissionMode, replacingIntent: changesPermissions)
        if changesPermissions {
            session.record.configChoices[SetConfigOptionParams.permissionChoiceKey] =
                params.permissionMode.flatMap { TaskPermissionMode(rawValue: $0)?.rawValue }
            try store.updateSession(session.record)
            publish(session)
        }
    }
}
