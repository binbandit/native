import ACP
import Foundation

extension AppModel {
    /// Publish only a confirmed selection. No working message is submitted here.
    func commitAgentModel(
        _ change: ComposerAgentChange, source: SessionModel, target: SessionModel, context: ContextTransfer?
    ) {
        guard let project = catalog.lookup(source.key)?.project else { return }
        source.isModelChangeSource = true
        target.continuedTaskKey = source.taskPresentationKey
        titles.rename(target.titleKey, to: source.displayTitle)
        if let context { sessions.services.modelContinuations.prepare(context, for: target.key) }
        if agentChangePlace(of: source) == .thisMac {
            deletedSessions.remove(target.key)
            if target.host == nil {
                unsentSessions.started(target.key, draft: source.draft)
            } else {
                unsentSessions.forget(target.key)
            }
            // A conversation returned to is listed already, in its task's project; it moves to the front.
            let listed = change.isReturn ? catalog.lookup(target.key)?.project ?? project : project
            if change.isReturn { catalog.remove(target.key) }
            catalog.add(
                SessionInfo(sessionId: target.id, cwd: source.cwd.folderPath, updatedAt: .now),
                for: target.agent.id, in: listed)
        } else {
            publishRemoteAgentChange(target, in: project)
        }
        sessions.services.titles.updateConfigChoices(for: target.titleKey) { saved in
            // A conversation replacement continues the task's restriction until an explicit pick.
            saved.requiresReadOnly = sessions.services.titles.configChoices(for: source.titleKey).requiresReadOnly
            for option in target.configOptions {
                if case .select(let value, _) = option.kind { saved.choose(option, value: value) }
            }
        }
        retainPrivateFiles(of: source, for: target.key)
        if change.isReturn {
            change.chainReturn = earlierConversations.returning(to: target.key, after: source.key)
        } else {
            earlierConversations.record(target.key, after: source.key)
            earlierConversations.keep(target.key)
        }
        moveAgentModelDraft(from: source, to: target)
        ordering.replace(source.key, with: target.key)
        taskPairs.replace(source.key, with: target.key)
        history.replace(source.key, with: target.key)
        if selection == source.key {
            selection = target.key
            target.wantsComposerFocus = true
        }
    }

    func undoAgentModel(_ change: ComposerAgentChange, source: SessionModel, target: SessionModel) {
        source.isModelChangeSource = false
        sessions.services.modelContinuations.remove(target.key)
        retainPrivateFiles(of: target, for: source.key)
        if let moved = change.chainReturn {
            earlierConversations.undoReturn(to: target.key, after: source.key, moved)
        } else {
            earlierConversations.undoSelection(target.key, restoring: source.key)
        }
        moveAgentModelDraft(from: target, to: source)
        ordering.replace(target.key, with: source.key)
        taskPairs.replace(target.key, with: source.key)
        history.replace(target.key, with: source.key)
        if selection == target.key { selection = source.key; source.wantsComposerFocus = true }
        // A conversation returned to was the task's before; it stays, without what was prepared for it.
        if change.isReturn {
            withdrawReturn(to: target)
        } else {
            deletedSessions.insert(target.key)
            discardAgentChange(target)
        }
    }

    private func moveAgentModelDraft(from source: SessionModel, to target: SessionModel) {
        target.adoptDiffCommentDrafts(from: source, moving: true)
        source.attachmentReads.move(to: target)
        target.draft = source.draft
        target.attachments = source.attachments
        target.quoteSelection = source.quoteSelection
        target.quoteSelectionSource = source.quoteSelectionSource
        source.draft = ""
        source.attachments = []
        source.quoteSelection = []
        source.quoteSelectionSource = nil
    }
}
