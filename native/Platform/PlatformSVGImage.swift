import ProjectIcons
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

/// Draws a checked SVG with the platform's own SVG support: AppKit's `NSImage` on the Mac. iPadOS
/// has no public SVG decoder (`UIImage(data:)` returns nil for SVG, and ImageIO lists no SVG type),
/// so there `canDraw` is false and callers fall back (docs/decisions.md, "SVG project icons").
nonisolated enum PlatformSVGImage {
    static var canDraw: Bool {
        #if canImport(AppKit)
        true
        #else
        false
        #endif
    }

    /// The icon fitted into a `side`-point square, rasterized at `scale` pixels per point so it's
    /// crisp at exactly that size. A glyph comes back as a template, to take the foreground it's
    /// shown in. Nil where the platform can't draw SVG.
    @MainActor static func image(_ icon: SVGIcon, side: CGFloat, scale: CGFloat) -> Image? {
        #if canImport(AppKit)
        guard let svg = NSImage(data: icon.data), svg.size.width > 0, svg.size.height > 0 else { return nil }
        let pixels = Int((side * scale).rounded(.up))
        guard pixels > 0,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        let fit = min(CGFloat(pixels) / svg.size.width, CGFloat(pixels) / svg.size.height)
        let drawn = CGSize(width: svg.size.width * fit, height: svg.size.height * fit)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        svg.draw(
            in: NSRect(
                x: (CGFloat(pixels) - drawn.width) / 2, y: (CGFloat(pixels) - drawn.height) / 2, width: drawn.width,
                height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = bitmap.cgImage else { return nil }
        let image = Image(decorative: cgImage, scale: scale)
        return icon.isGlyph ? image.renderingMode(.template) : image
        #else
        nil
        #endif
    }
}
