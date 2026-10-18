import ACP
import Foundation

extension AppModel: UsageLimitsHost {
    func resumableSession(_ target: UsageSessionRef) async -> (any LimitResumable)? {
        let key = SessionKey(agent: target.agent, id: target.session)
        if session(key) == nil {
            // Starts the agent first if it isn't running yet.
            await loadSession(key)
        }
        return session(key)
    }

    func setUsageLimit(_ message: String?, for agent: AgentDefinition.ID) {
        sendGate.setUsageLimit(message, for: agent)
    }

    func show(_ target: UsageSessionRef) {
        // A subagent shows inside its parent's task.
        selection = SessionKey(agent: target.agent, id: target.parent ?? target.session)
    }
}

extension AppModel: UsageNotificationsHost {
    func isShowing(_ ref: UsageSessionRef) -> Bool {
        selection == SessionKey(agent: ref.agent, id: ref.parent ?? ref.session)
    }

    func isUserTask(_ ref: UsageSessionRef) -> Bool {
        model(for: ref)?.origin == .user
    }

    func lastTurnSummary(of ref: UsageSessionRef) -> TurnSummary? {
        guard let state = model(for: ref)?.state, let turn = state.turns.last else { return nil }
        return state.summary(of: turn)
    }

    func canReplyInText(_ ref: UsageSessionRef) -> Bool {
        model(for: ref)?.pendingQuestion.flatMap { Self.textField(of: $0.request) } != nil
    }

    func answerPermission(of ref: UsageSessionRef, allow: Bool) async {
        guard let session = model(for: ref), let pending = session.state.pendingPermissions.first else { return }
        let kinds: [PermissionOption.Kind] = allow ? [.allowOnce, .allowAlways] : [.rejectOnce, .rejectAlways]
        let option = kinds.lazy.compactMap { kind in pending.permission.options.first { $0.kind == kind } }.first
        guard let option else { return }
        await session.choose(option, forToolCall: pending.toolCallID)
    }

    func reply(to ref: UsageSessionRef, text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session = model(for: ref), let question = session.pendingQuestion,
            let field = Self.textField(of: question.request)
        else { return false }
        await session.answerQuestion([field: .string(text)])
        return true
    }

    private func model(for ref: UsageSessionRef) -> SessionModel? {
        session(SessionKey(agent: ref.agent, id: ref.session))
    }

    /// The question's one field, when it has exactly one and that takes free text.
    private static func textField(of request: CreateElicitationRequest) -> String? {
        guard case .object(let properties)? = request.requestedSchema?["properties"], properties.count == 1,
            let (name, field) = properties.first, field["type"]?.stringValue == "string", field["enum"] == nil
        else { return nil }
        return name
    }
}

extension AppModel: UsageReportingHost {
    func reportingSession(for agent: AgentDefinition.ID) -> (any ContextReporting)? {
        sessions.open(of: agent).first { $0.acceptsPrompts && $0.isIdleForContext }
    }

    func taskUsage(of agent: AgentDefinition.ID) -> [UsageTaskSpend] {
        sessions.open(of: agent)
            .filter(\.acceptsPrompts)
            .compactMap { session in
                guard let usage = session.state.usage else { return nil }
                return UsageTaskSpend(
                    id: session.id, title: session.displayTitle, contextUsed: usage.used, contextSize: usage.size,
                    cost: usage.cost)
            }
            .sorted { ($0.cost?.amount ?? 0, $0.contextUsed) > ($1.cost?.amount ?? 0, $1.contextUsed) }
    }

    func activityBackfill() -> [ActivityBackfill] {
        projects.all.flatMap { project in
            agents.flatMap { runtime in
                catalog.sessions(in: project.id, of: runtime.agent.id).compactMap { info in
                    info.updatedDate.map { date in
                        ActivityBackfill(
                            agent: runtime.agent.id.rawValue, agentName: runtime.agent.displayName,
                            session: info.sessionId.rawValue, title: info.title, project: info.cwd, updatedAt: date)
                    }
                }
            }
        }
    }
}
