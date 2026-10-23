import Foundation
import Testing

@testable import ACP

struct ArtifactViewportTests {
    @Test func pinchKeepsThePointUnderTheFingers() {
        var viewport = ArtifactViewport()
        viewport.resize(image: CGSize(width: 1200, height: 800), container: CGSize(width: 600, height: 400))
        viewport.setZoom(2, anchor: CGPoint(x: 150, y: 100))
        #expect(viewport.offset == CGSize(width: -150, height: -100))
        viewport.setZoom(1, anchor: CGPoint(x: 150, y: 100))
        #expect(viewport.offset == .zero)
    }

    @Test func fitsWithoutUpscalingAndKeepsImageReachable() {
        var viewport = ArtifactViewport()
        viewport.resize(image: CGSize(width: 1200, height: 800), container: CGSize(width: 600, height: 500))
        #expect(viewport.fitScale == 0.5)
        #expect(viewport.drawnSize == CGSize(width: 600, height: 400))
        viewport.setZoom(2)
        viewport.pan(by: CGSize(width: 1000, height: -1000))
        #expect(viewport.offset == CGSize(width: 300, height: -150))
        viewport.fit()
        #expect(viewport.offset == .zero)
        #expect(viewport.zoom == 1)
    }

    @Test func resizingAndZoomingOutClampThePan() {
        var viewport = ArtifactViewport()
        viewport.resize(image: CGSize(width: 400, height: 300), container: CGSize(width: 600, height: 500))
        #expect(viewport.fitScale == 1)
        viewport.setZoom(4)
        viewport.pan(by: CGSize(width: 500, height: 500))
        viewport.resize(image: CGSize(width: 400, height: 300), container: CGSize(width: 1200, height: 1000))
        #expect(viewport.offset == CGSize(width: 200, height: 100))
        viewport.setZoom(0.5)
        #expect(viewport.offset == .zero)
        viewport.setZoom(.infinity)
        viewport.pan(by: CGSize(width: CGFloat.nan, height: 0))
        #expect(viewport.zoom == 0.5)
        #expect(viewport.offset == .zero)
    }
}
