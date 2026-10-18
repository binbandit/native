import SwiftUI

// The editor's keys (docs/keyboard.md), mapped by the pure `ComposerKeyMap`.
extension ComposerView {
    func handleKey(_ press: KeyPress, suggestions: ComposerSuggestions?) -> KeyPress.Result {
        guard let key = ComposerKeyMap.Key(press.key) else { return .ignored }
        let context = ComposerKeyMap.Context(
            isSuggestionListOpen: suggestions != nil,
            isDraftEmpty: session.draft.isEmpty,
            isWorking: isWorking,
            hasQueuedPrompts: !session.queuedPrompts.isEmpty,
            hasLastPrompt: session.state.lastPrompt != nil,
            hasAttachments: !session.attachments.isEmpty,
            isComposing: PlatformTextInput.isComposing,
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
        case .recallLastPrompt:
            session.draft = session.state.lastPrompt ?? ""
        case .editLastQueuedPrompt:
            if let last = session.queuedPrompts.last {
                edit(last)
            }
        case .removeLastAttachment:
            removeLastAttachment()
        case .submit(let behavior):
            submit(behavior)
        // Focus moves in `handleKey`, which needs to know whether it did.
        case .moveFocus, .swallow:
            break
        }
    }

}
