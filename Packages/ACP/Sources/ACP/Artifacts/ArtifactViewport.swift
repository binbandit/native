import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Image navigation in points, independent of the pointer, touch or keyboard that drives it.
public struct ArtifactViewport: Equatable, Sendable {
    public private(set) var zoom: Double = 1
    public private(set) var offset: CGSize = .zero
    public private(set) var imageSize: CGSize = .zero
    public private(set) var containerSize: CGSize = .zero

    public init() {}

    public var fitScale: Double {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(containerSize.width / imageSize.width, containerSize.height / imageSize.height, 1)
    }

    public var drawnSize: CGSize {
        CGSize(width: imageSize.width * fitScale * zoom, height: imageSize.height * fitScale * zoom)
    }

    public mutating func resize(image: CGSize, container: CGSize) {
        guard image.width.isFinite, image.height.isFinite, container.width.isFinite, container.height.isFinite,
            image.width > 0, image.height > 0, container.width > 0, container.height > 0
        else { return }
        imageSize = image
        containerSize = container
        clampOffset()
    }

    public mutating func setZoom(_ value: Double, anchor: CGPoint = .zero) {
        guard value.isFinite else { return }
        let next = min(max(value, 0.25), 16)
        let point = anchor.x.isFinite && anchor.y.isFinite ? anchor : .zero
        offset = CGSize(
            width: point.x + (offset.width - point.x) * next / zoom,
            height: point.y + (offset.height - point.y) * next / zoom)
        zoom = next
        clampOffset()
    }

    public mutating func pan(by translation: CGSize) {
        guard translation.width.isFinite, translation.height.isFinite else { return }
        offset.width += translation.width
        offset.height += translation.height
        clampOffset()
    }

    public mutating func fit() {
        zoom = 1
        offset = .zero
    }

    private mutating func clampOffset() {
        let horizontal = max(0, (drawnSize.width - containerSize.width) / 2)
        let vertical = max(0, (drawnSize.height - containerSize.height) / 2)
        offset.width = min(max(offset.width, -horizontal), horizontal)
        offset.height = min(max(offset.height, -vertical), vertical)
    }
}
