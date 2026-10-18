import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// What Open In needs from the platform: which catalog apps are installed and their icons, opening a
/// location in one, and the clipboard. On the Mac that's NSWorkspace. iPadOS can't hand a host's
/// folder to another app, so it finds none and Open In offers Copy Path alone.
@MainActor
enum OpenInPlatform {
    /// Posted when the app comes to the front, when apps may have been installed or removed.
    static var didBecomeActive: Notification.Name {
        #if canImport(AppKit)
        NSApplication.didBecomeActiveNotification
        #else
        UIApplication.didBecomeActiveNotification
        #endif
    }

    /// The installed catalog apps, in catalog order. On the Mac, Finder is always among them.
    static func installedApps() -> [OpenInApp] {
        #if canImport(AppKit)
        OpenInTarget.catalog.compactMap { target in
            let workspace = NSWorkspace.shared
            let url = target.bundleIdentifiers.lazy.compactMap(workspace.urlForApplication(withBundleIdentifier:)).first
            guard let url else { return nil }
            // Finder keeps ".app" when the user shows all filename extensions.
            var name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            if name.hasSuffix(".app") {
                name.removeLast(4)
            }
            return OpenInApp(target: target, url: url, name: name)
        }
        #else
        []
        #endif
    }

    /// The app's own icon at menu size, read from its installed bundle: Native never ships other
    /// apps' icons.
    static func icon(for app: OpenInApp) -> Image {
        #if canImport(AppKit)
        Image(nsImage: menuIcon(for: app))
        #else
        Image(systemName: "app")
        #endif
    }

    /// Opens the location in the app and brings the app to the front.
    static func open(_ location: OpenInLocation, in app: OpenInApp) async throws {
        #if canImport(AppKit)
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        switch (location, app.target.launch) {
        case (.local(let folder), .document):
            try await workspace.open([folder], withApplicationAt: app.url, configuration: configuration)
        case (.local(let folder), .arguments(let arguments)):
            // A running app ignores launch arguments, so these always start a new process.
            configuration.arguments = arguments + [folder.path(percentEncoded: false)]
            configuration.createsNewApplicationInstance = true
            try await workspace.openApplication(at: app.url, configuration: configuration)
        case (.remote(let host, let path), _):
            guard let url = app.target.remoteURL(host: host, path: path) else { return }
            try await workspace.open([url], withApplicationAt: app.url, configuration: configuration)
        }
        #endif
    }

    static func copy(_ string: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    /// Shows why an app couldn't open the folder (moved, damaged, refused it), as the system words it.
    static func present(_ error: any Error) {
        #if canImport(AppKit)
        NSApplication.shared.presentError(error)
        #endif
    }

    #if canImport(AppKit)
    private static var icons: [URL: NSImage] = [:]

    /// The icon as AppKit menus take it, at the 16pt macOS menus draw app icons (Finder's Open With).
    static func menuIcon(for app: OpenInApp) -> NSImage {
        if let icon = icons[app.url] {
            return icon
        }
        let icon = NSWorkspace.shared.icon(forFile: app.url.path(percentEncoded: false))
        icon.size = NSSize(width: 16, height: 16)
        icons[app.url] = icon
        return icon
    }
    #endif
}
