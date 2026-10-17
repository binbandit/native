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
            Button("Open") { NSWorkspace.shared.open(root.appending(path: path)) }
        }
        #endif
        if let root, PlatformFileBrowser.canReveal {
            Button("Reveal in Finder") { PlatformFileBrowser.reveal(root.appending(path: path)) }
        }
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
