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
            editingQueued = nil
            selection = nil
        }
    }

    /// Sends the draft; while the agent works, queues or steers it, or saves the queued message
    /// being edited. Says what happened, or why nothing could.
    func submit(_ behavior: FollowUpBehavior) {
        let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // `/goal …` is Native's own; it never reaches the agent.
        if let command = GoalCommand(parsing: session.draft), let goal = automation.goal(for: session) {
            session.draft = ""
            Task { await goal.perform(command) }
            return
        }
        if let blocker {
            feedback = .blocked(blocker)
            return
        }
        if let id = editingQueued, session.queuedPrompts.contains(where: { $0.id == id }) {
            session.updateQueued(id, text: text)
            editingQueued = nil
            session.draft = ""
            feedback = .updatedInQueue
            return
        }
        // The queued message may have gone out while it was being edited; then it's a new message.
        editingQueued = nil
        if session.canSend, !session.queuedPrompts.isEmpty {
            // After a cancelled turn paused the queue: the draft API sends the waiting messages
            // first, then this one; each turn shows in the transcript.
            Task { await session.submit(behavior) }
            return
        }
        session.draft = ""
        Task {
            do {
                let delivery = try await session.submit(text, behavior)
                feedback = ComposerFeedback(delivery: delivery, requested: behavior, supportsSteering: session.supportsSteering, agentName: session.agentName)
            } catch {
                // Nothing went out, so the message comes back to be sent again.
                if session.draft.isEmpty {
                    session.draft = text
                }
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
        isFocused = true
    }

    func edit(_ prompt: SessionModel.QueuedPrompt) {
        editingQueued = prompt.id
        session.draft = prompt.text
        isFocused = true
    }

    func remove(_ id: SessionModel.QueuedPrompt.ID) {
        if editingQueued == id {
            editingQueued = nil
            session.draft = ""
        }
        session.removeQueued(id, undoManager: undoManager)
        feedback = .removedFromQueue
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

    func insertMentions(_ urls: [URL]) {
        session.draft = FileMentions.draft(session.draft, mentioning: urls, relativeTo: session.cwd)
        isFocused = true
    }
}
