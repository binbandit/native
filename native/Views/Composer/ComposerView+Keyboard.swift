import ACP
import SwiftUI

// The editor's keys (docs/keyboard.md), mapped by the pure `ComposerKeyMap`, and the attachment
// chips' token-field keys, by `DraftAttachmentKeys`.
extension ComposerView {
    func handleKey(_ press: KeyPress, suggestions: ComposerSuggestions?) -> KeyPress.Result {
        if !(press.key == .escape && overlayDismissal != nil), let result = handleAttachmentKey(press) { return result }
        guard let key = ComposerKeyMap.Key(press.key) else { return .ignored }
        let context = ComposerKeyMap.Context(
            isSuggestionListOpen: suggestions != nil,
            hasOverlay: overlayDismissal != nil,
            isDraftEmpty: session.draft.isEmpty,
            isWorking: isWorking,
            hasQueuedPrompts: !session.queuedPrompts.isEmpty,
            isEditingQueued: session.editingQueuedPrompt != nil,
            canStop: session.canCancel,
            hasLastPrompt: session.state.lastPrompt != nil,
            isComposing: PlatformTextInput.isComposing,
            isInCodeBlock: isCaretInCodeBlock,
            preferredFollowUp: followUp
        )
        let modifiers = ComposerKeyMap.Modifiers(press)
        guard
            let action = ComposerKeyMap.action(
                for: key, modifiers: modifiers, isRepeat: press.phase == .repeat, in: context)
        else {
            return .ignored
        }
        if case .moveFocus(let forward) = action {
            return ComposerPlatform.moveKeyFocus(forward: forward) ? .handled : .ignored
        }
        perform(action, suggestions: suggestions)
        return .handled
    }

    func perform(_ action: ComposerKeyMap.Action, suggestions: ComposerSuggestions?) {
        switch action {
        case .moveHighlight(let delta):
            highlighted = min(max(highlighted + delta, 0), (suggestions?.count ?? 1) - 1)
        case .insertHighlightedSuggestion:
            switch suggestions {
            case .commands(let commands) where commands.indices.contains(highlighted):
                insert(commands[highlighted])
            case .files(let files, let query) where files.indices.contains(highlighted):
                insert(files[highlighted], for: query)
            default:
                break
            }
        case .closeSuggestionList:
            suggestionsDismissed = true
        case .dismissOverlay:
            overlayDismissal?.dismiss()
        case .recallLastPrompt:
            session.draft = session.state.lastPrompt ?? ""
        case .editLastQueuedPrompt:
            if let last = session.queuedPrompts.last {
                edit(last)
            }
        case .submit(let behavior):
            submit(behavior)
        case .sendQueuedNow:
            if let id = session.editingQueuedPrompt {
                sendNow(id, savingDraft: true)
            }
        case .cancelQueuedEdit:
            stopEditingQueued()
        case .moveQueued(let up):
            if let id = session.editingQueuedPrompt {
                session.moveQueued(id, up ? .up : .down)
            }
        case .stop:
            stop()
        case .codeNewline:
            editCode { PromptCode.newline(in: $0, replacing: $1) }
        case .codeIndent:
            editCode { PromptCode.indent(in: $0, selection: $1) }
        case .codeOutdent:
            editCode { PromptCode.outdent(in: $0, selection: $1) }
        // Focus moves in `handleKey`, which needs to know whether it did.
        case .moveFocus, .swallow:
            break
        }
    }

    /// The chips' keys, ahead of the editor's: nil leaves the key to them; otherwise the key stops
    /// here.
    private func handleAttachmentKey(_ press: KeyPress) -> KeyPress.Result? {
        let attachments = session.attachments
        let draft = DraftAttachmentKeys.Draft(
            isEmpty: session.draft.isEmpty, isCaretAtStart: isCaretAtStart,
            isComposing: PlatformTextInput.isComposing)
        let outcome = DraftAttachmentKeys.outcome(
            for: DraftAttachmentKeys.Key(press), selection: selectedAttachmentIndex, count: attachments.count,
            draft: draft, isRepeat: press.phase == .repeat)
        if let index = outcome.removing, attachments.indices.contains(index) {
            removeAttachment(attachments[index].id)
        }
        selectAttachment(at: outcome.selection)
        return outcome.passesKey ? nil : .handled
    }

    /// The caret before the first character with nothing selected, where ← reaches the chips.
    private var isCaretAtStart: Bool {
        guard case .selection(let range)? = selection?.indices else { return session.draft.isEmpty }
        return range.isEmpty && range.lowerBound == session.draft.startIndex
    }
}
