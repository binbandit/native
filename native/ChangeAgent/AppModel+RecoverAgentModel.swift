import ACP
import Foundation

extension AppModel {
    /// An in-app adapter may forget a conversation that has never received a prompt. Restore the
    /// confirmed selection before moving the locally prepared context to its replacement id.
    func recoverAgentModel(_ old: SessionKey, in replacement: SessionModel) async throws {
        let oldTitle = SessionTitles.Key(agent: old.agent, session: old.id)
        let chosen = titles.configChoices(for: oldTitle)
        await replacement.adoptConfigChoices(chosen)
        guard let confirmed = sessions.services.modelContinuations.receipt(for: old)?.confirmedChoices,
            !confirmed.isEmpty
        else {
            throw ComposerAgentChange.Failure(
                "The previous model choice couldn't be restored safely. Choose the earlier conversation.")
        }
        for (id, initial) in confirmed {
            let expected = chosen.choices[id]?.value ?? initial
            guard let option = replacement.configOptions.first(where: { $0.id == id }),
                case .select(let actual, _) = option.kind, actual == expected,
                !PolicyPermissionModes.forbids(option, value: actual)
            else {
                throw ComposerAgentChange.Failure(
                    "Couldn't restore the selected model and permissions. Try again when the agent is ready.")
            }
        }
        if let name = titles.namedTitle(for: oldTitle) { titles.rename(replacement.titleKey, to: name) }
        sessionHooks.taskRecovered(old, replacement)
        sessions.services.modelContinuations.replace(old, with: replacement.key)
        earlierConversations.replace(old, with: replacement.key)
        if let original = sessions.session(old) {
            replacement.continuedTaskKey = original.taskPresentationKey
            replacement.modelChange = original.modelChange
            original.modelChange?.replace(original, with: replacement)
            original.attachmentReads.move(to: replacement)
        }
        restoreAgentModelChoice(for: replacement)
    }
}
