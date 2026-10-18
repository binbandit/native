import SwiftUI

extension View {
    /// The rounded, hairline-bordered content surface of the plan. It's also the container shape
    /// that nested surfaces round concentrically with.
    func transcriptCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return background(.fill.quinary, in: shape)
            .overlay { shape.strokeBorder(.separator) }
            .containerShape(shape)
    }

    /// Fills and outlines a nested surface (code blocks, diffs). `ConcentricRectangle` can't
    /// `strokeBorder`, so a double width stroke is clipped to the shape, leaving 1pt inside it.
    func nestedSurface(_ fill: some ShapeStyle, minimumRadius: CGFloat) -> some View {
        let shape = ConcentricRectangle.rect(corners: .concentric(minimum: .fixed(minimumRadius)), isUniform: true)
        return background(fill, in: shape)
            .overlay { shape.stroke(.separator, lineWidth: 2) }
            .clipShape(shape)
    }

    /// Sweeps a highlight across text while `isActive`, the way running tool rows read as busy.
    func shimmering(_ isActive: Bool) -> some View {
        Shimmer(content: self, isActive: isActive)
    }
}

/// Details rise into place: a short slide up with a fade and a slight blur.
struct RevealTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(y: phase.isIdentity ? 0 : 8)
            .scaleEffect(phase.isIdentity ? 1 : 0.985, anchor: .topLeading)
            .blur(radius: phase.isIdentity ? 0 : 2)
    }
}

extension Animation {
    /// The expand curve: fast start, long soft landing, so details arrive quickly without a jolt.
    static let reveal = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)
}

/// A chevron that points right when collapsed and down when expanded.
struct DisclosureChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
    }
}

/// Shows its content at natural height up to `maxHeight`, scrolling beyond that. A scroll view's
/// ideal height is its content's, so fixing the frame to its ideal size caps it without measuring.
struct HeightCappedScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical) {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The highlight sweeping over busy text: a copy of the text in the primary color, drawn once, seen
/// through a band Core Animation moves (`ShimmerBandLayer`), so it costs nothing per frame.
private struct Shimmer<Content: View>: View {
    let content: Content
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isActive, !reduceMotion {
            content.overlay {
                LayerMaskedView(content: Rectangle().fill(Color.primary).mask { content }) {
                    ShimmerBandLayer()
                }
            }
        } else {
            content
        }
    }
}
