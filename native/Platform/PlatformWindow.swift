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
}
