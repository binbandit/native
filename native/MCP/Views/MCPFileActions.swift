import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Showing an agent's configuration file. Files are on the host, so these only work where the UI
/// runs on the host too; elsewhere `canReveal` is false and views show the path to copy instead.
enum MCPFileActions {
    #if canImport(AppKit)
    static let canReveal = true

    static func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([url.resolvingSymlinksInPath()])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
    #else
    static let canReveal = false

    static func reveal(_ url: URL) {}
    #endif
}
