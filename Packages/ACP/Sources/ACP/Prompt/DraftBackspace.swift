import Foundation

/// What Backspace does in a draft that carries files, decided before the text view applies it.
/// With nothing typed, the first press takes off the last file, as in a token field. A held key
/// (still emptying the text) and text being composed with an input method are left alone.
public enum DraftBackspace: Equatable, Sendable {
    case removeLastAttachment
    /// Nothing happens, and the text view doesn't hear the key either (it would only beep).
    case swallow

    /// Nil leaves the key to the text view, which deletes text as usual.
    public init?(isDraftEmpty: Bool, isComposing: Bool, hasAttachments: Bool, isRepeat: Bool) {
        guard isDraftEmpty, !isComposing, hasAttachments else { return nil }
        self = isRepeat ? .swallow : .removeLastAttachment
    }
}
