import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// What the focused text view is doing with the keyboard, for views that act on keys before it.
enum PlatformTextInput {
    /// Whether an input method is composing text (marked text, as Japanese and Chinese input do) in
    /// the focused text view. The keys are its own then: Return picks a candidate, Backspace edits
    /// the composition, Escape cancels it. SwiftUI's `onKeyPress` hears them first all the same.
    /// iPadOS gives no reliable way to ask, so it says no.
    static var isComposing: Bool {
        #if canImport(AppKit)
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
        #else
        false
        #endif
    }
}

extension View {
    /// Delete or Forward Delete while this view has keyboard focus: the Mac's Delete command, or the
    /// keys themselves on iPadOS.
    func onDeleteKey(perform: @escaping () -> Void) -> some View {
        #if os(macOS)
        onDeleteCommand(perform: perform)
        #else
        onKeyPress(keys: [.delete, .deleteForward]) { _ in
            perform()
            return .handled
        }
        #endif
    }
}
