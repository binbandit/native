import CoreGraphics
import Foundation
import ImageIO
import ProjectIcons
import UniformTypeIdentifiers

/// Finds the icons a project already has: a web favicon or logo where common frameworks put them
/// (SVG or bitmap), else an Apple app icon from an asset catalog. Bitmaps come back as small PNGs
/// and SVGs as checked files, so results can be cached and cross actors freely.
nonisolated struct ProjectIconResolver: Sendable {
    let files: any ProjectFileReading

    /// A file in the project that can be its icon.
    struct FoundIcon: Identifiable, Hashable, Sendable {
        /// Relative to the project's folder.
        let path: String
        let artwork: ProjectIconArtwork

        var id: String { path }
    }

    /// Icons in the order they're tried. SVGs lead, since they're crisp at any size.
    static let candidates = [
        "public/favicon.svg", "favicon.svg", "app/icon.svg", "src/app/icon.svg", "static/favicon.svg",
        "assets/favicon.svg", "public/icon.svg", "icon.svg", "public/logo.svg", "logo.svg", "assets/icon.svg",
        "assets/logo.svg", "src/assets/logo.svg", ".github/logo.svg",
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
    /// A bitmap icon's pixel size: crisp at 16pt on any display and at the 32pt Settings preview.
    static let pixelSize = 128
    /// Found SVGs wider or taller than this are wordmarks, not icons, and aren't picked on their own.
    private static let maximumAutomaticAspect = 2.0

    /// The project's icon: `preferred` (a path the user chose) while it's still there and readable,
    /// else the first candidate that reads, else an app icon. Nil when it has none Native can draw.
    @concurrent func detectIcon(in root: URL, preferring preferred: String? = nil) async -> FoundIcon? {
        if let preferred, let icon = await icon(atPath: preferred, in: root) {
            return icon
        }
        for path in Self.candidates {
            if let icon = await icon(atPath: path, in: root), Self.isIconShaped(icon.artwork) {
                return icon
            }
        }
        return await appIcon(in: root)
    }

    /// Every icon the project has, for the picker: each candidate that reads, wordmarks included,
    /// then the app icon.
    @concurrent func foundIcons(in root: URL) async -> [FoundIcon] {
        var found: [FoundIcon] = []
        for path in Self.candidates {
            if let icon = await icon(atPath: path, in: root) { found.append(icon) }
        }
        if let appIcon = await appIcon(in: root) { found.append(appIcon) }
        // The same picture under two names (public/favicon.svg and favicon.svg) shows once.
        var seen = Set<ProjectIconArtwork>()
        return found.filter { seen.insert($0.artwork).inserted }
    }

    /// The icon in the file at `path`, if it's one Native can draw.
    func icon(atPath path: String, in root: URL) async -> FoundIcon? {
        guard let data = await files.data(atPath: path, in: root, limit: Self.sizeLimit),
            let artwork = try? ProjectIconArtwork.decode(data, isSVG: path.lowercased().hasSuffix(".svg"))
        else { return nil }
        return FoundIcon(path: path, artwork: artwork)
    }

    private static func isIconShaped(_ artwork: ProjectIconArtwork) -> Bool {
        guard case .svg(let icon) = artwork, let aspect = icon.aspectRatio else { return true }
        return max(aspect, 1 / aspect) <= maximumAutomaticAspect
    }

    /// The largest image in the first `AppIcon.appiconset` found within `catalogDepth` folders, else
    /// in another app-icon set there (`AppIcon-Light.imageset`, as projects with alternate icons
    /// keep them).
    private func appIcon(in root: URL) async -> FoundIcon? {
        var frontier = [""]
        var alternates: [String] = []
        for _ in 0..<Self.catalogDepth {
            var next: [String] = []
            for directory in frontier {
                for name in await files.entries(atPath: directory, in: root) ?? [] {
                    let path = directory.isEmpty ? name : "\(directory)/\(name)"
                    if name == "AppIcon.appiconset" {
                        return await largestImage(inCatalogSet: path, root: root)
                    }
                    if name.hasPrefix("AppIcon"), name.hasSuffix(".appiconset") || name.hasSuffix(".imageset") {
                        alternates.append(path)
                    } else if !name.hasPrefix("."), !Self.skippedDirectories.contains(name),
                        !name.contains(".") || name.hasSuffix(".xcassets")
                    {
                        next.append(path)
                    }
                }
            }
            frontier = next
        }
        // The default look first when the names say which it is.
        let preferred = alternates.sorted { (Self.alternateRank($0), $0) < (Self.alternateRank($1), $1) }
        for path in preferred.prefix(3) {
            if let icon = await largestImage(inCatalogSet: path, root: root) { return icon }
        }
        return nil
    }

    private static func alternateRank(_ path: String) -> Int {
        let name = path.lowercased()
        if name.contains("original") || name.contains("default") { return 0 }
        return name.contains("light") ? 1 : 2
    }

    private func largestImage(inCatalogSet path: String, root: URL) async -> FoundIcon? {
        let names = await files.entries(atPath: path, in: root) ?? []
        // Without reading Contents.json, the biggest PNG by name ("1024", "512@2x") is a fine guess,
        // and decoding picks whichever is really largest among the first few.
        let pngs = names.filter { $0.lowercased().hasSuffix(".png") }
            .sorted { Self.sizeHint($0) > Self.sizeHint($1) }
        for name in pngs.prefix(3) {
            if let icon = await icon(atPath: "\(path)/\(name)", in: root) { return icon }
        }
        return nil
    }

    /// The largest number in a file name times its scale suffix, e.g. "icon_512x512@2x" is 1024.
    private static func sizeHint(_ name: String) -> Int {
        let numbers = name.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let scale = name.contains("@3x") ? 3 : name.contains("@2x") ? 2 : 1
        return (numbers.filter { $0 > 3 }.max() ?? 0) * scale
    }

    /// Decodes a bitmap (PNG, JPEG, ICO and the rest ImageIO reads), picks its largest frame, and
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
