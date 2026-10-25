import ACP
import NativeAutomation
import SwiftUI

// What the composer's controls and keys do, through the session's model methods.
extension ComposerView {
    func draftChanged() {
        highlighted = 0
        if SlashCommandQuery(draft: draftText) == nil, mentionQuery == nil {
            suggestionsDismissed = false
        }
        if session.draft.isEmpty {
            session.editingQueuedPrompt = nil
            agentCommandDraft = nil
            selection = nil
        }
    }

    /// Sends the draft; while the agent works, queues or steers it, or saves the queued message
    /// being edited. Says what happened, or why nothing could.
    func submit(_ behavior: FollowUpBehavior) {
        let text = PromptQuote.trimmed(session.draft)
        let attachments = session.attachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        if let page {
            guard attachmentsBlockedReason == nil, !flagMissingAttachments() else { return }
            page.start()
            return
        }
        // `/clear` and `/goal …` are Native's own and never reach the agent, unless the user picked
        // the agent's command of that name from the list. They read the message the way the list
        // offered them, without its quotes, and leave the quotes for the next message.
        let message = draftText
        let isAgentCommand = agentCommandDraft.map(message.hasPrefix) ?? false
        if !isAgentCommand, ClearConversationCommand.matches(message) {
            clearConversation()
            return
        }
        if !isAgentCommand, let command = GoalCommand(parsing: message), let goal = automation.goal(for: session) {
            draftText = ""
            Task { await goal.perform(command) }
            return
        }
        if let blocked = session.sendBlockedReason ?? attachmentsBlockedReason {
            feedback = .blocked(blocked)
            return
        }
        if flagMissingAttachments() {
            return
        }
        if let id = session.editingQueuedPrompt, !text.isEmpty, session.queuedPrompts.contains(where: { $0.id == id }) {
            session.updateQueued(id, text: text)
            session.editingQueuedPrompt = nil
            session.draft = ""
            feedback = .updatedInQueue
            return
        }
        // The queued message may have gone out while it was being edited; then it's a new message.
        session.editingQueuedPrompt = nil
        if session.canSend, !session.queuedPrompts.isEmpty {
            // After a cancelled turn paused the queue: the draft API sends the waiting messages
            // first, then this one; each turn shows in the transcript.
            Task { await session.submit(behavior) }
            return
        }
        session.draft = ""
        session.attachments = []
        let wasWorking = isWorking
        Task {
            do {
                let delivery = try await session.submit(text, attaching: attachments, behavior)
                feedback = ComposerFeedback(
                    delivery: delivery, requested: behavior, wasWorking: wasWorking,
                    supportsSteering: session.supportsSteering, agentName: session.agentName,
                    heldFor: session.turnHold)
            } catch {
                // Nothing went out, so the message and its files come back to be sent again.
                if session.draft.isEmpty {
                    session.draft = text
                }
                session.attachments = attachments + session.attachments
                feedback = .failed(error)
            }
        }
    }

    func insert(_ path: String, for query: FileMentionQuery) {
        let (text, cursor) = query.draft(draftText, inserting: path)
        draftText = text
        selection = TextSelection(insertionPoint: cursor)
        mentionSource?.noteMentioned(path)
        isFocused = true
    }

    /// Tab, Return or a click on a listed command: the caret goes after it, ready for its argument.
    func insert(_ command: ComposerSlashCommand) {
        let (text, cursor) = SlashCommandQuery.draft(draftText, inserting: command)
        draftText = text
        selection = TextSelection(insertionPoint: cursor)
        agentCommandDraft = command.isNative ? nil : draftText
        isFocused = true
    }

    /// `/clear`: a fresh conversation in this task (AppModel+ClearConversation.swift). The message
    /// comes back if it can't start, with why.
    func clearConversation() {
        let message = draftText
        draftText = ""
        Task {
            do {
                try await app.clearConversation(of: session)
            } catch {
                if draftText.isEmpty {
                    draftText = message
                }
                feedback = .blocked(error.localizedDescription)
            }
        }
    }

    func edit(_ prompt: SessionModel.QueuedPrompt) {
        session.editingQueuedPrompt = prompt.id
        session.draft = prompt.text
        isFocused = true
    }

    /// Closes the queued message open in the editor without saving the edits.
    func stopEditingQueued() {
        session.editingQueuedPrompt = nil
        session.draft = ""
    }

    func remove(_ id: SessionModel.QueuedPrompt.ID) {
        if session.editingQueuedPrompt == id {
            stopEditingQueued()
        }
        session.removeQueued(id, undoManager: undoManager)
        feedback = .removedFromQueue
    }

    /// Sends a queued message ahead of the rest ("Send Now"); `savingDraft` keeps the edits made to
    /// it in the editor first.
    func sendNow(_ id: SessionModel.QueuedPrompt.ID, savingDraft: Bool = false) {
        guard let route = session.sendNowRoute else { return }
        if session.editingQueuedPrompt == id {
            if savingDraft {
                session.updateQueued(id, text: session.draft)
            }
            stopEditingQueued()
        }
        feedback = ComposerFeedback(sendingNow: route, agentName: session.agentName)
        Task { await session.sendQueuedNow(id) }
    }

    /// Stops the running turn; the placeholder says it's stopping until the agent confirms. Pressed
    /// again while the agent hasn't, it stops waiting.
    func stop() {
        Task { await session.cancel() }
    }

    func undo() {
        undoManager?.undo()
        feedback = nil
    }

    func set(_ setting: SelectSetting, to value: String) {
        Task { await session.pick(setting.option, value: value) }
    }

    func apply(_ change: ComposerSettings.Change?) {
        if let change {
            set(change.setting, to: change.value)
        }
    }
}
