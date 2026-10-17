import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Finds the icon a project already has: a web favicon or logo where frameworks put them (the paths
/// Conductor checks), else an Apple app icon from an asset catalog. Returns a small PNG, so the
/// result can be cached and crosses actors freely.
nonisolated struct ProjectIconResolver: Sendable {
    let files: any ProjectFileReading

    /// Icons in the order they're tried. SVGs are left out: ImageIO can't draw them.
    static let candidates = [
        "public/apple-touch-icon.png", "apple-touch-icon.png",
        "public/favicon.png", "public/icon.png", "public/logo.png",
        "favicon.png", "logo.png", "icon.png",
        "app/icon.png", "src/app/icon.png", "app/apple-icon.png", "src/app/apple-icon.png",
        ".github/logo.png",
        "public/favicon.ico", "favicon.ico", "app/favicon.ico", "src/app/favicon.ico",
        "static/favicon.ico", "static/favicon.png",
        "assets/favicon.ico", "assets/favicon.png", "assets/icon.png",
        "src-tauri/icons/icon.png", "src/assets/icon.png",
    ]

    /// Folders never searched for an asset catalog: dependencies, build output, VCS data.
    private static let skippedDirectories: Set<String> = [
        ".git", "node_modules", "Pods", "Carthage", "DerivedData", "build", ".build", "dist", "target", "vendor",
    ]

    /// How deep to look for an `AppIcon.appiconset`: `App/Assets.xcassets/AppIcon.appiconset` is 3.
    private static let catalogDepth = 4
    /// Icon files are small; anything bigger isn't one.
    private static let sizeLimit = 2 * 1024 * 1024
    /// The cached icon's pixel size: crisp at 16pt on any display, room for larger uses.
    static let pixelSize = 64

    /// The project's icon as a `pixelSize` PNG, or nil when it has none Native can read.
    @concurrent func detectIcon(in root: URL) async -> Data? {
        for path in Self.candidates {
            if let data = await files.data(atPath: path, in: root, limit: Self.sizeLimit),
                let png = Self.thumbnail(of: data, maxPixelSize: Self.pixelSize)
            {
                return png
            }
        }
        return await appIcon(in: root)
    }

    /// The largest image in the first `AppIcon.appiconset` found within `catalogDepth` folders.
    private func appIcon(in root: URL) async -> Data? {
        var frontier = [""]
        for _ in 0..<Self.catalogDepth {
            var next: [String] = []
            for directory in frontier {
                for name in await files.entries(atPath: directory, in: root) ?? [] {
                    let path = directory.isEmpty ? name : "\(directory)/\(name)"
                    if name == "AppIcon.appiconset" {
                        return await largestImage(inCatalogSet: path, root: root)
                    }
                    if !name.hasPrefix("."), !Self.skippedDirectories.contains(name),
                        !name.contains(".") || name.hasSuffix(".xcassets")
                    {
                        next.append(path)
                    }
                }
            }
            frontier = next
        }
        return nil
    }

    private func largestImage(inCatalogSet path: String, root: URL) async -> Data? {
        let names = await files.entries(atPath: path, in: root) ?? []
        // Without reading Contents.json, the biggest PNG by name ("1024", "512@2x") is a fine guess,
        // and decoding picks whichever is really largest among the first few.
        let pngs = names.filter { $0.lowercased().hasSuffix(".png") }
            .sorted { Self.sizeHint($0) > Self.sizeHint($1) }
        for name in pngs.prefix(3) {
            if let data = await files.data(atPath: "\(path)/\(name)", in: root, limit: Self.sizeLimit),
                let png = Self.thumbnail(of: data, maxPixelSize: Self.pixelSize)
            {
                return png
            }
        }
        return nil
    }

    /// The largest number in a file name times its scale suffix, e.g. "icon_512x512@2x" is 1024.
    private static func sizeHint(_ name: String) -> Int {
        let numbers = name.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let scale = name.contains("@3x") ? 3 : name.contains("@2x") ? 2 : 1
        return (numbers.filter { $0 > 3 }.max() ?? 0) * scale
    }

    /// Decodes an image (PNG, JPEG, ICO and the rest ImageIO reads), picks its largest frame, and
    /// re-encodes it as a PNG no larger than `maxPixelSize`.
    static func thumbnail(of data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        // .ico files hold several sizes; start from the largest.
        let index = (0..<CGImageSourceGetCount(source)).max { pixelWidth(source, $0) < pixelWidth(source, $1) } ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func pixelWidth(_ source: CGImageSource, _ index: Int) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    }
}
