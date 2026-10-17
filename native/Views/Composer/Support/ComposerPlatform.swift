import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// The few things the composer does differently on the Mac and on iPad, kept here so the rest of it
/// is platform-neutral SwiftUI.
enum ComposerPlatform {
    /// Moves keyboard focus to the next or previous control, as Tab does outside a text view.
    /// Returns false where the system should handle Tab itself (iPad's focus system).
    @discardableResult
    static func moveKeyFocus(forward: Bool) -> Bool {
        #if canImport(AppKit)
        guard let window = NSApp.keyWindow else { return false }
        if forward {
            window.selectNextKeyView(nil)
        } else {
            window.selectPreviousKeyView(nil)
        }
        return true
        #else
        return false
        #endif
    }

    /// Controls that appear on hover elsewhere stay visible where there's no pointer to hover with.
    static var revealsControlsOnHover: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }

    /// Where `@` mentions find files: git on the Mac. An iPad has no local checkout; it will ask its
    /// host instead.
    static func fileIndex(for root: URL) -> (any ProjectFileIndex)? {
        #if os(macOS)
        GitProjectFileIndex(root: root)
        #else
        nil
        #endif
    }

    /// Keyboard hints in placeholders only make sense where a keyboard is the norm.
    static var showsKeyboardHints: Bool {
        #if os(iOS)
        false
        #else
        true
        #endif
    }
}
