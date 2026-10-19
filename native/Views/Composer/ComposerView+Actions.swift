import ACP
import NativeAutomation
import SwiftUI

// What the composer's controls and keys do, through the session's model methods.
extension ComposerView {
    func draftChanged() {
        highlighted = 0
        if SlashCommandQuery(draft: session.draft) == nil, mentionQuery == nil {
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
        let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = session.attachments
        guard !text.isEmpty || !attachments.isEmpty else { return }
        // `/clear` and `/goal …` are Native's own and never reach the agent, unless the user picked
        // the agent's command of that name from the list.
        let isAgentCommand = agentCommandDraft.map(session.draft.hasPrefix) ?? false
        if !isAgentCommand, ClearConversationCommand.matches(session.draft) {
            clearConversation()
            return
        }
        if !isAgentCommand, let command = GoalCommand(parsing: session.draft), let goal = automation.goal(for: session)
        {
            session.draft = ""
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
                    supportsSteering: session.supportsSteering, agentName: session.agentName)
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
        let (text, cursor) = query.draft(session.draft, inserting: path)
        session.draft = text
        selection = TextSelection(insertionPoint: cursor)
        mentionSource?.noteMentioned(path)
        isFocused = true
    }

    func insert(_ command: ComposerSlashCommand) {
        session.draft = SlashCommandQuery.draft(inserting: command)
        agentCommandDraft = command.isNative ? nil : session.draft
        isFocused = true
    }

    /// `/clear`: a fresh conversation in this task (AppModel+ClearConversation.swift). The draft
    /// comes back if it can't start, with why.
    func clearConversation() {
        let draft = session.draft
        session.draft = ""
        Task {
            do {
                try await app.clearConversation(of: session)
            } catch {
                if session.draft.isEmpty {
                    session.draft = draft
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
        Task { await session.setConfigOption(setting.option, to: value) }
    }

    func apply(_ change: ComposerSettings.Change?) {
        if let change {
            set(change.setting, to: change.value)
        }
    }
}
