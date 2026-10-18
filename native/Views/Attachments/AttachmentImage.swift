import ImageIO
import SwiftUI

/// An attached image drawn from its bytes, decoded off the main actor at the size it shows, so a
/// screenshot doesn't decode at full size for a chip.
struct AttachmentImage: View {
    let data: Data
    /// The longest edge it's drawn at, in points.
    let maxSide: CGFloat
    /// `.fill` crops it to the frame it's given; `.fit` shows all of it, sized by its own shape.
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.dsFill)
            }
        }
        .aspectRatio(contentMode == .fit ? aspectRatio : nil, contentMode: .fit)
        .task(id: data) {
            image = await Self.decode(data, maxPixels: Int(maxSide * displayScale))
        }
    }

    /// Width over height, once it's decoded; a photo's shape until then.
    private var aspectRatio: CGFloat {
        guard let image, image.height > 0 else { return 4 / 3 }
        return CGFloat(image.width) / CGFloat(image.height)
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
