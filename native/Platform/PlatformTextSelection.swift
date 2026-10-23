import Foundation

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Reads only Native's own focused text view. No pasteboard, Accessibility permission or other
/// application's selection is involved.
@MainActor
enum PlatformTextSelection {
    static func capture() -> String? {
        #if canImport(AppKit)
        guard
            let window = NSApp.keyWindow ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })
        else { return nil }
        if let view = window.firstResponder as? NSTextView,
            view.selectedRange().length > 0,
            let range = Range(view.selectedRange(), in: view.string)
        {
            return String(view.string[range])
        }
        // SwiftUI's selectable prose exposes selection on its local accessibility element,
        // rather than making an NSTextView the first responder.
        let focused = window.accessibilityFocusedUIElement as? any NSAccessibilityProtocol
        return focused?.accessibilitySelectedText().flatMap { $0.isEmpty ? nil : $0 }
        #else
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.isKeyWindow {
                if let selected = selectedText(in: window) { return selected }
            }
        }
        return nil
        #endif
    }

    #if !canImport(AppKit)
    private static func selectedText(in view: UIView) -> String? {
        if view.isFirstResponder, let input = view as? any UITextInput,
            let range = input.selectedTextRange, !range.isEmpty
        {
            return input.text(in: range)
        }
        for child in view.subviews {
            if let text = selectedText(in: child) { return text }
        }
        return nil
    }
    #endif
}
