#if DEBUG
import ACP
import CoreGraphics
import Foundation
import ImageIO

enum ArtifactPreviewFixtures {
    static let imageData: Data = {
        let width = 600, height = 400
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Data() }
        context.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.24, green: 0.44, blue: 0.71, alpha: 1))
        context.fill(CGRect(x: 70, y: 80, width: 180, height: 240))
        context.setFillColor(CGColor(red: 0.36, green: 0.61, blue: 0.51, alpha: 1))
        context.fill(CGRect(x: 350, y: 80, width: 180, height: 240))
        context.setFillColor(CGColor(red: 0.3, green: 0.33, blue: 0.38, alpha: 1))
        context.fill(CGRect(x: 250, y: 195, width: 100, height: 10))
        let data = NSMutableData()
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return data as Data
    }()

    static func image() -> ArtifactViewerModel { .preview(data: imageData) }
    static func loading() -> ArtifactViewerModel { .preview(loading: true) }
    static func unavailable() -> ArtifactViewerModel {
        .preview(error: "This file is missing or can't be read. Check the file, then try again.")
    }
}
#endif
