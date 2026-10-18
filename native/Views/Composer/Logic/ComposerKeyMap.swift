import ACP

/// The composer editor's keys, as docs/keyboard.md lays them out (Sending, Slash commands, File
/// mentions).
/// Pure, so the table can be tested without a text view.
enum ComposerKeyMap {
    enum Key {
        case up, down, `return`, tab, escape, delete
    }

    struct Modifiers: OptionSet {
        let rawValue: Int

        static let shift = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let command = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    /// What the composer knows when a key comes in.
    struct Context {
        /// The slash-command or file-mention list.
        var isSuggestionListOpen: Bool
        var isDraftEmpty: Bool
        var isWorking: Bool
        var hasQueuedPrompts: Bool
        var hasLastPrompt: Bool
        var hasAttachments: Bool
        var preferredFollowUp: FollowUpBehavior
    }

    enum Action: Equatable {
        case moveHighlight(by: Int)
        case insertHighlightedSuggestion
        case closeSuggestionList
        case recallLastPrompt
        case editLastQueuedPrompt
        /// Backspace with nothing typed takes off the last attached file, as in a token field.
        case removeLastAttachment
        case submit(FollowUpBehavior)
        /// Tab moves on to the controls rather than typing a tab character.
        case moveFocus(forward: Bool)
        /// Nothing happens, but the text view doesn't get the key either.
        case swallow
    }

    /// The action for a key, or nil to let the text view handle it. `isRepeat` is a held key.
    static func action(for key: Key, modifiers: Modifiers, isRepeat: Bool, in context: Context) -> Action? {
        if context.isSuggestionListOpen, modifiers.isEmpty || key == .escape {
            switch key {
            case .up: return .moveHighlight(by: -1)
            case .down: return .moveHighlight(by: 1)
            case .return, .tab: return isRepeat ? .swallow : .insertHighlightedSuggestion
            case .escape: return .closeSuggestionList
            case .delete: return nil
            }
        }
        switch key {
        case .up where modifiers.isEmpty && context.isDraftEmpty:
            if context.isWorking {
                return context.hasQueuedPrompts ? .editLastQueuedPrompt : nil
            }
            return context.hasLastPrompt ? .recallLastPrompt : nil
        // Shift- and Option-Return fall through to the text view as a newline.
        case .return where modifiers.isEmpty || modifiers == .command:
            guard !isRepeat else { return .swallow }
            let preferred = context.preferredFollowUp
            return .submit(modifiers == .command ? preferred.opposite : preferred)
        case .tab where modifiers.isEmpty || modifiers == .shift:
            return isRepeat ? .swallow : .moveFocus(forward: modifiers.isEmpty)
        // Where the platform hands Delete to the editor's key handler (iPadOS); the Mac's text view
        // keeps it, so the composer hears it through `onDraftBackspace` and the same rule.
        case .delete where modifiers.isEmpty:
            switch DraftBackspace(
                isDraftEmpty: context.isDraftEmpty, isComposing: false, hasAttachments: context.hasAttachments,
                isRepeat: isRepeat)
            {
            case .removeLastAttachment: return .removeLastAttachment
            case .swallow: return .swallow
            case nil: return nil
            }
        // The Stop button takes Escape through its shortcut; swallowed otherwise, so the text view
        // doesn't open its completion list.
        case .escape:
            return .swallow
        default:
            return nil
        }
    }
}
