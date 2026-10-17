import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Shows files in the platform's file browser: the Finder on the Mac. iPadOS has no equivalent for
/// a host's files, so callers hide the action there (`canReveal` is false).
enum PlatformFileBrowser {
    static var canReveal: Bool {
        #if canImport(AppKit)
        true
        #else
        false
        #endif
    }

    /// Opens a Finder window with `url` selected.
    static func reveal(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}
