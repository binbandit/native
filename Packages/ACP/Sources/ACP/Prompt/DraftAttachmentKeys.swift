import Foundation

/// The keys that reach a draft's attachment chips from its text, as in a token field. With the
/// caret at the start of the text, ← selects the last chip and further ← walks left; → walks
/// right and, past the last chip, back to the text; Delete or Forward Delete takes off the
/// selected chip; Escape, or typing anything else, returns to the text. With nothing typed,
/// Backspace takes off the last chip straight away. A held key never removes a chip, and every key
/// belongs to an input method while it composes text.
public enum DraftAttachmentKeys {
    public enum Key: Sendable {
        case left, right, backspace, forwardDelete, escape
        /// Any other key: typing, Return, the other arrows.
        case other
    }

    /// Where the text is when the key comes in.
    public struct Draft: Sendable {
        public var isEmpty: Bool
        /// The caret sits before the first character, with nothing selected.
        public var isCaretAtStart: Bool
        /// An input method is composing text (marked text).
        public var isComposing: Bool

        public init(isEmpty: Bool, isCaretAtStart: Bool, isComposing: Bool = false) {
            self.isEmpty = isEmpty
            self.isCaretAtStart = isCaretAtStart || isEmpty
            self.isComposing = isComposing
        }
    }

    public struct Outcome: Equatable, Sendable {
        /// The chip to take off, by its index before removal.
        public var removing: Int?
        /// The chip selected afterwards, by index once `removing` is gone; nil is the text.
        public var selection: Int?
        /// Whether the text view still gets the key.
        public var passesKey: Bool

        public init(removing: Int? = nil, selection: Int?, passesKey: Bool) {
            self.removing = removing
            self.selection = selection
            self.passesKey = passesKey
        }
    }

    /// What `key` does, given the selected chip (nil while the caret is in the text) among `count`.
    public static func outcome(
        for key: Key, selection: Int?, count: Int, draft: Draft, isRepeat: Bool
    ) -> Outcome {
        let selection = selection.flatMap { count > 0 ? min(max($0, 0), count - 1) : nil }
        guard !draft.isComposing, count > 0 else { return Outcome(selection: nil, passesKey: true) }
        guard let selected = selection else {
            return fromText(key, count: count, draft: draft, isRepeat: isRepeat)
        }
        switch key {
        case .left:
            return Outcome(selection: max(selected - 1, 0), passesKey: false)
        case .right:
            return Outcome(selection: selected + 1 < count ? selected + 1 : nil, passesKey: false)
        case .backspace, .forwardDelete:
            guard !isRepeat else { return Outcome(selection: selected, passesKey: false) }
            let remaining = count - 1
            // Backspace walks on to the chip before; Forward Delete to the one that takes its place.
            let next =
                key == .backspace
                ? (selected > 0 ? selected - 1 : 0) : min(selected, remaining - 1)
            return Outcome(removing: selected, selection: remaining > 0 ? next : nil, passesKey: false)
        case .escape:
            return Outcome(selection: nil, passesKey: false)
        case .other:
            return Outcome(selection: nil, passesKey: true)
        }
    }

    private static func fromText(_ key: Key, count: Int, draft: Draft, isRepeat: Bool) -> Outcome {
        switch key {
        // A held ← moving through the text stops at its start rather than running on into the chips.
        case .left where draft.isCaretAtStart && !isRepeat:
            return Outcome(selection: count - 1, passesKey: false)
        // A held Backspace only empties the text; it takes a fresh press to start on the chips.
        case .backspace where draft.isEmpty:
            return isRepeat
                ? Outcome(selection: nil, passesKey: false)
                : Outcome(removing: count - 1, selection: nil, passesKey: false)
        default:
            return Outcome(selection: nil, passesKey: true)
        }
    }
}
