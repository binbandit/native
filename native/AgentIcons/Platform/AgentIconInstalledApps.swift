import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif

/// Icons of apps installed on this device, for agents that come with one (Claude, Codex, Cursor).
/// The Mac asks Launch Services. iPadOS can't see other apps' icons, so there it finds none and
/// agents use their registry icon or a monogram instead.
nonisolated enum AgentIconInstalledApps {
    /// The icon of the first app in `bundleIDs` that's installed, rendered `pixelSize` pixels square.
    /// Any thread: it draws into its own bitmap.
    static func icon(bundleIDs: [String], pixelSize: Int) -> CGImage? {
        #if canImport(AppKit)
        let workspace = NSWorkspace.shared
        guard let app = bundleIDs.lazy.compactMap(workspace.urlForApplication(withBundleIdentifier:)).first else {
            return nil
        }
        let icon = workspace.icon(forFile: app.path(percentEncoded: false))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Drawing at the exact size lets AppKit pick the icon's best representation for it.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
        #else
        return nil
        #endif
    }
}
