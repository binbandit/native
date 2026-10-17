import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Menu items for a changed file that depend on the platform: on a Mac whose host holds the files,
/// open and reveal them; everywhere, copy the path.
struct GitFileMenuItems: View {
    let path: String
    /// The repository's root on this machine; `nil` when the files live on another host.
    let root: URL?

    var body: some View {
        #if os(macOS)
        if let root {
            let url = root.appending(path: path)
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        #endif
        Button("Copy Path") { Self.copy(path) }
    }

    private static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
