import ImageIO
import SwiftUI

/// An attached image drawn from its bytes, decoded off the main actor at the size it shows, so a
/// screenshot doesn't decode at full size for a chip.
struct AttachmentImage: View {
    let data: Data
    /// The longest edge it's drawn at, in points.
    let maxSide: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.dsFill)
            }
        }
        .task(id: data) {
            image = await Self.decode(data, maxPixels: Int(maxSide * displayScale))
        }
    }

    @concurrent
    private static func decode(_ data: Data, maxPixels: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 1),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
