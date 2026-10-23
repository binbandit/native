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
            if let fitting {
                AttachmentImageFitLayout(size: fittedSize(in: fitting)) {
                    content
                }
            } else {
                content
            }
        }
        .task(id: data) {
            image = await Self.decode(data, maxPixels: Int(maxSide * displayScale))
        }
    }

    private var content: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.dsFill)
            }
        }
    }

    /// The largest size of the image's shape (a photo's, until it's decoded) within `fitting`.
    private func fittedSize(in fitting: CGSize) -> CGSize {
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

/// Keeps a fitted image's aspect ratio when a narrow message offers less than its maximum width.
private struct AttachmentImageFitLayout: Layout {
    let size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, (proposal.width ?? size.width) / size.width, (proposal.height ?? size.height) / size.height)
        return CGSize(width: size.width * max(0, scale), height: size.height * max(0, scale))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
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
