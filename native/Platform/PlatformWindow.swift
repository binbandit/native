import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// The frontmost window, as the platform sees it.
@MainActor
enum PlatformWindow {
    /// The key window's undo manager, for commands the menu bar runs: a focused value isn't there
    /// when the window's focus is outside SwiftUI's reach. iPadOS has no menu-bar-wide undo
    /// manager to reach for, so commands there go without undo.
    static var keyUndoManager: UndoManager? {
        #if canImport(AppKit)
        (NSApp.keyWindow ?? NSApp.mainWindow)?.undoManager
        #else
        nil
        #endif
    }

    static func undo(using manager: UndoManager?) {
        guard let manager else { return }
        #if canImport(AppKit)
        if performTextUndo("undo:", using: manager) { return }
        #endif
        manager.undo()
    }

    static func redo(using manager: UndoManager?) {
        guard let manager else { return }
        #if canImport(AppKit)
        if performTextUndo("redo:", using: manager) { return }
        #endif
        manager.redo()
    }

    #if canImport(AppKit)
    private static func performTextUndo(_ selector: String, using manager: UndoManager) -> Bool {
        // Use the editor's action to finish its editing transaction, then publish a storage
        // change so SwiftUI's binding follows an explicitly invoked menu command.
        guard let window = NSApp.windows.first(where: { $0.undoManager === manager }),
            let editor = window.firstResponder as? NSTextView, editor.undoManager === manager
        else { return false }
        let previous = editor.string
        let handled = editor.tryToPerform(NSSelectorFromString(selector), with: nil)
        if handled, editor.string != previous { editor.didChangeText() }
        return handled
    }
    #endif
}
