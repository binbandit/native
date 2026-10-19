import CoreGraphics
import Foundation
import ImageIO
import ProjectIcons
import SwiftUI

/// A project icon's picture as Native keeps it: a small PNG made from a bitmap (favicon, app icon,
/// a picked photo), or the SVG itself, drawn fresh for each size it's shown at.
nonisolated enum ProjectIconArtwork: Hashable, Sendable {
    case png(Data)
    case svg(SVGIcon)

    /// Pixels per point an icon is drawn at: crisp on every display, from a 1x Mac to a 3x iPad.
    static let drawingScale: CGFloat = 4

    /// Reads a file's bytes as an icon: an SVG Native can draw safely, or any bitmap ImageIO reads,
    /// made into a `ProjectIconResolver.pixelSize` PNG. Throws why it can't be one.
    static func decode(_ data: Data, isSVG: Bool? = nil) throws(ProjectIconRejection) -> ProjectIconArtwork {
        if isSVG ?? SVGIcon.isLikelySVG(data) {
            guard PlatformSVGImage.canDraw else { throw .svgUnsupportedHere }
            do {
                return .svg(try SVGIcon(checking: data))
            } catch {
                throw .svg(error)
            }
        }
        guard let png = ProjectIconResolver.thumbnail(of: data, maxPixelSize: ProjectIconResolver.pixelSize) else {
            throw .notAnImage
        }
        return .png(png)
    }

    /// What it's saved as on disk, next to the project's id.
    var fileExtension: String {
        switch self {
        case .png: "png"
        case .svg: "svg"
        }
    }

    var data: Data {
        switch self {
        case .png(let data): data
        case .svg(let icon): icon.data
        }
    }

    /// Reads one back from disk, by its extension.
    static func load(from url: URL) -> ProjectIconArtwork? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        switch url.pathExtension {
        case "svg": return (try? SVGIcon(checking: data)).map(ProjectIconArtwork.svg)
        case "png": return .png(data)
        default: return nil
        }
    }

    /// The picture for a `side`-point square. Nil when it can't be drawn here (an SVG on iPadOS).
    @MainActor func image(side: CGFloat) -> Image? {
        switch self {
        case .png(let data):
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }
            return Image(decorative: image, scale: CGFloat(image.width) / side)
        case .svg(let icon):
            return PlatformSVGImage.image(icon, side: side, scale: Self.drawingScale)
        }
    }
}

/// Why a file can't be a project icon, worded for the picker.
nonisolated enum ProjectIconRejection: Error, Hashable {
    case notAnImage
    case svg(SVGIcon.Rejection)
    case svgUnsupportedHere

    var message: String {
        switch self {
        case .notAnImage: "That file isn't an image Native can read. Try an SVG, PNG, JPEG or ICO."
        case .svg(let rejection): "Native can't use that SVG. \(rejection.reason)"
        case .svgUnsupportedHere: "This device can't draw SVG icons. Try a PNG or JPEG."
        }
    }
}
