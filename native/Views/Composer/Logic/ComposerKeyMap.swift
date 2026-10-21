/// The composer editor's keys, as docs/keyboard.md lays them out (Sending, Code, Slash commands,
/// File mentions).
/// Pure, so the table can be tested without a text view.
enum ComposerKeyMap {
    enum Key {
        case up, down, `return`, tab, escape
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
        /// A screen overlay owns Escape ahead of the editor's local actions.
        var hasOverlay = false
        var isDraftEmpty: Bool
        var isWorking: Bool
        var hasQueuedPrompts: Bool
        /// A queued message is open in the editor.
        var isEditingQueued = false
        /// There's a turn (or a retry) for Escape to stop.
        var canStop = false
        var hasLastPrompt: Bool
        /// An input method is composing text, so every key is its own.
        var isComposing: Bool
        /// The caret is in a fenced code block (`PromptCode.isInBlock`).
        var isInCodeBlock = false
        var preferredFollowUp: FollowUpBehavior
    }

    enum Action: Equatable {
        case moveHighlight(by: Int)
        case insertHighlightedSuggestion
        case closeSuggestionList
        case dismissOverlay
        case recallLastPrompt
        case editLastQueuedPrompt
        case submit(FollowUpBehavior)
        /// Sends the queued message being edited now, with the edits.
        case sendQueuedNow
        /// Closes the queued message being edited, leaving it as it was.
        case cancelQueuedEdit
        /// Moves the queued message being edited sooner (`true`) or later in the queue.
        case moveQueued(up: Bool)
        case stop
        /// Tab moves on to the controls rather than typing a tab character.
        case moveFocus(forward: Bool)
        /// In a code block: a new line indented like the caret's, one indent in, or one out.
        case codeNewline, codeIndent, codeOutdent
        /// Nothing happens, but the text view doesn't get the key either.
        case swallow
    }

    /// The action for a key, or nil to let the text view handle it. `isRepeat` is a held key.
    static func action(for key: Key, modifiers: Modifiers, isRepeat: Bool, in context: Context) -> Action? {
        guard !context.isComposing else { return nil }
        if key == .escape, context.hasOverlay {
            return isRepeat ? .swallow : .dismissOverlay
        }
        if context.isSuggestionListOpen, modifiers.isEmpty || key == .escape {
            switch key {
            case .up: return .moveHighlight(by: -1)
            case .down: return .moveHighlight(by: 1)
            case .return, .tab: return isRepeat ? .swallow : .insertHighlightedSuggestion
            case .escape: return .closeSuggestionList
            }
        }
        // In a code block, Return and Tab edit the code, and ⌘Return does what Return does elsewhere.
        if context.isInCodeBlock {
            switch key {
            case .return where modifiers.isEmpty: return .codeNewline
            case .return where modifiers == .command:
                return isRepeat ? .swallow : .submit(context.preferredFollowUp)
            case .tab where modifiers.isEmpty: return .codeIndent
            case .tab where modifiers == .shift: return .codeOutdent
            default: break
            }
        }
        switch key {
        // Session ▸ Move Up / Down take these first when the menu bar can; this covers the rest.
        case .up where modifiers == [.command, .option] && context.isEditingQueued:
            return .moveQueued(up: true)
        case .down where modifiers == [.command, .option] && context.isEditingQueued:
            return .moveQueued(up: false)
        case .up where modifiers.isEmpty && context.isDraftEmpty:
            // Queued messages first: they're what's about to go out (or waiting after a stop).
            if context.hasQueuedPrompts {
                return .editLastQueuedPrompt
            }
            return !context.isWorking && context.hasLastPrompt ? .recallLastPrompt : nil
        // Shift- and Option-Return fall through to the text view as a newline.
        case .return where modifiers.isEmpty || modifiers == .command:
            guard !isRepeat else { return .swallow }
            if context.isEditingQueued, modifiers == .command {
                return .sendQueuedNow
            }
            let preferred = context.preferredFollowUp
            return .submit(modifiers == .command ? preferred.opposite : preferred)
        case .tab where modifiers.isEmpty || modifiers == .shift:
            return isRepeat ? .swallow : .moveFocus(forward: modifiers.isEmpty)
        // Handled here rather than by the Stop button's shortcut, which never sees the key while the
        // editor has it. Otherwise swallowed, so the text view doesn't open its completion list.
        case .escape:
            if isRepeat { return .swallow }
            if context.isEditingQueued { return .cancelQueuedEdit }
            return context.canStop ? .stop : .swallow
        default:
            return nil
        }
    }
}
