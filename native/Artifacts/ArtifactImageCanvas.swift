import ACP
import SwiftUI

struct ArtifactImageCanvas: View {
    let image: CGImage
    let model: ArtifactViewerModel
    @State private var dragTranslation: CGSize = .zero
    @State private var pinchStart: Double?
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: model.viewport.drawnSize.width, height: model.viewport.drawnSize.height)
                .offset(model.viewport.offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(.rect)
                .onTapGesture(count: 2, perform: model.toggleZoom)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            model.pan(
                                by: CGSize(
                                    width: value.translation.width - dragTranslation.width,
                                    height: value.translation.height - dragTranslation.height))
                            dragTranslation = value.translation
                        }
                        .onEnded { _ in dragTranslation = .zero }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if pinchStart == nil { pinchStart = model.viewport.zoom }
                            model.setZoom(
                                (pinchStart ?? 1) * value.magnification,
                                anchor: CGPoint(
                                    x: (value.startAnchor.x - 0.5) * geometry.size.width,
                                    y: (value.startAnchor.y - 0.5) * geometry.size.height))
                        }
                        .onEnded { _ in pinchStart = nil }
                )
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    model.resize($0)
                }
        }
        .clipped()
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in
            if press.modifiers.contains(.command), press.characters == "+" {
                model.zoom(by: 1.25)
                return .handled
            }
            let step = DS.Artifact.keyboardPan
            switch press.key {
            case .leftArrow: model.pan(by: CGSize(width: step, height: 0))
            case .rightArrow: model.pan(by: CGSize(width: -step, height: 0))
            case .upArrow: model.pan(by: CGSize(width: 0, height: step))
            case .downArrow: model.pan(by: CGSize(width: 0, height: -step))
            default: return .ignored
            }
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image preview")
        .accessibilityHint(
            DS.isTouchPlatform
                ? "Pinch or double-tap to zoom. Drag or use arrow keys to pan."
                : "Pinch or double-click to zoom. Drag or use arrow keys to pan."
        )
        .accessibilityAction(named: "Zoom In") { model.zoom(by: 1.25) }
        .accessibilityAction(named: "Zoom Out") { model.zoom(by: 0.8) }
        .accessibilityAction(named: "Fit", model.fit)
    }
}

#if DEBUG
#Preview("Artifact image - Zoom and pan") {
    DSPreviewPair {
        ArtifactViewer(model: ArtifactPreviewFixtures.image())
            .frame(width: 640, height: 480)
    }
}
#endif
