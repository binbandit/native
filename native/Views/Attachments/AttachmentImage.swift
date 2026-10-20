import ImageIO
import SwiftUI

/// An attached image drawn from its bytes, decoded off the main actor at the size it shows, so a
/// screenshot doesn't decode at full size for a chip.
struct AttachmentImage: View {
    let data: Data
    /// The longest edge it's drawn at, in points.
    let maxSide: CGFloat
    /// Shows all of it at its own shape within this size; without one it fills (and crops to) the
    /// frame it's given.
    var fitting: CGSize?

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
        .frame(width: fittedSize?.width, height: fittedSize?.height)
        .task(id: data) {
            image = await Self.decode(data, maxPixels: Int(maxSide * displayScale))
        }
    }

    /// The largest size of the image's shape (a photo's, until it's decoded) within `fitting`.
    private var fittedSize: CGSize? {
        guard let fitting else { return nil }
        let ratio = image.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? 4 / 3
        let height = min(fitting.height, fitting.width / ratio)
        return CGSize(width: height * ratio, height: height)
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

#if DEBUG
#Preview("Attachment image") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            // Filling a chip's square, fitted to a message's box, and still decoding (no bytes).
            AttachmentImage(data: ComposerPreviewFixtures.screenshot, maxSide: 32)
                .frame(width: 32, height: 32)
                .clipShape(.rect(cornerRadius: DS.Radius.small))
            AttachmentImage(
                data: ComposerPreviewFixtures.screenshot, maxSide: 240, fitting: CGSize(width: 240, height: 160))
            AttachmentImage(data: Data(), maxSide: 120, fitting: CGSize(width: 120, height: 90))
        }
    }
}
#endif
