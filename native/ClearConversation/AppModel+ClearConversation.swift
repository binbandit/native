import ACP
import Foundation

// `/clear`: a fresh conversation in the same task. The agent's context starts over in a new session
// (same agent, folder, settings and title), which takes the task's place in the sidebar. The earlier
// conversation isn't lost: it stays with the agent, one click away (`EarlierConversationButton`).
extension AppModel {
    enum ClearConversationError: LocalizedError {
        case nothingToClear
        case working(agent: String)

        var errorDescription: String? {
            switch self {
            case .nothingToClear: "There's nothing to clear yet."
            case .working(let agent): "\(agent) is still working. Stop it first (Esc), then /clear."
            }
        }
    }

    /// Starts a fresh conversation in `old`'s task and selects it. `old` keeps its transcript and
    /// opens from the new one.
    @discardableResult
    func clearConversation(of old: SessionModel) async throws -> SessionModel {
        if let reason = coordinatorConversationBlock(for: old.key) {
            throw CoordinatorTaskFailure(reason)
        }
        guard old.hasStarted, old.acceptsPrompts else { throw ClearConversationError.nothingToClear }
        guard old.phase == .idle, !old.isRunningHiddenCommand else {
            throw ClearConversationError.working(agent: old.agentName)
        }
        guard let runtime = await ensureRunning(old.agent.id) else {
            throw SessionLauncher.LaunchError.agentUnavailable(old.agentName)
        }
        if let reason = coordinatorConversationBlock(for: old.key) { throw CoordinatorTaskFailure(reason) }
        let session = try await launcher.start(
            on: runtime, cwd: old.cwd, project: catalog.lookup(old.key)?.project, continuing: old)
        await session.adoptSettings(of: old)
        if let project = catalog.lookup(old.key)?.project {
            catalog.add(
                SessionInfo(sessionId: session.id, cwd: old.cwd.folderPath, updatedAt: .now), for: old.agent.id,
                in: project)
        }
        earlierConversations.record(session.key, after: old.key)
        ordering.replace(old.key, with: session.key)
        // The task keeps its name; a fresh conversation would otherwise be named after its first prompt.
        if let title = titles.title(for: old.titleKey, agentTitle: old.title) {
            titles.rename(session.titleKey, to: title)
        }
        session.addNotice(
            "Fresh conversation: \(old.agentName) starts without the earlier context, which stays under Earlier Conversation in the toolbar.",
            isError: false)
        history.replace(old.key, with: session.key)
        if selection == old.key {
            selection = session.key
            session.wantsComposerFocus = true
        }
        return session
    }

    /// Opens the conversation `/clear` set aside before `key`, or the one that replaced it.
    func openConversation(_ direction: ConversationDirection, from key: SessionKey) {
        let target =
            switch direction {
            case .earlier: earlierConversations.conversation(before: key)
            case .later: earlierConversations.conversation(after: key)
            }
        if let target {
            selection = target
        }
    }

    enum ConversationDirection {
        case earlier, later
    }

    /// Keeps a `/clear` across launches once its fresh conversation sends its first message.
    func keepClearedConversation(after event: SessionEvent) {
        guard case .promptSent(let context, _) = event, let id = context.sessionID else { return }
        earlierConversations.keep(SessionKey(agent: context.agent, id: id))
    }
}

extension SessionModel {
    /// Takes on `other`'s settings (model first, since it can change what the rest offer), so a
    /// fresh conversation carries on with the same model, effort, autonomy and modes.
    fileprivate func adoptSettings(of other: SessionModel) async {
        let isModel: (ConfigOption) -> Bool = { $0.category == "model" }
        for option in other.configOptions.filter(isModel) + other.configOptions.filter({ !isModel($0) }) {
            guard case .select(let value, _) = option.kind,
                let mine = configOptions.first(where: { $0.id == option.id }),
                case .select(let current, let choices) = mine.kind, current != value,
                choices.contains(where: { $0.value == value })
            else { continue }
            await setConfigOption(mine, to: value)
        }
    }
}
