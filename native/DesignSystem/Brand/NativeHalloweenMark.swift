import SwiftUI

/// The Halloween edition of Native's emblem, from the seasonal app icons
/// (`design/app-icon/Halloween*.icon`): each link of `NativeMark` as a little ghost, with two eyes cut
/// out near its top and drips under it. Colored per edition (Regular, Beta, Nightly) in the icons'
/// palettes, for light and dark.
///
/// It lays out exactly like `NativeMark`, so it can stand in for it; the drips hang below that
/// frame, about a fifth of its height, without affecting layout.
///
/// The eyes and drips are translated from the icons' `upper-fold.svg` and `lower-fold.svg` into the
/// emblem's units; regenerate them from those files rather than editing points by hand.
public struct NativeHalloweenMark: View {
    let edition: NativeHalloweenEdition

    @Environment(\.colorScheme) private var colorScheme

    public init(edition: NativeHalloweenEdition) {
        self.edition = edition
    }

    public var body: some View {
        Color.clear
            .aspectRatio(NativeMark.aspectRatio, contentMode: .fit)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    ghosts(markSize: proxy.size)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Native")
            .accessibilityAddTraits(.isImage)
    }

    private func ghosts(markSize: CGSize) -> some View {
        let palette = edition.palette(isDark: colorScheme == .dark)
        return Canvas { context, _ in
            let rect = CGRect(origin: .zero, size: markSize)
            for (link, color) in [(NativeMark.Link.left, palette.lowerFold), (NativeMark.Link.right, palette.upperFold)] {
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [color.mix(with: .white, by: Self.sheen), color]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: markSize.height * Self.dripExtent)
                )
                var body = NativeMark(link: link).path(in: rect)
                body.addPath(Self.path(link == .left ? Self.lowerEyes : Self.upperEyes, width: markSize.width))
                // Even-odd, so the eyes are holes the page shows through, as the tile does in the icon.
                context.fill(body, with: shading, style: FillStyle(eoFill: true))
                context.fill(Self.path(link == .left ? Self.lowerDrips : Self.upperDrips, width: markSize.width), with: shading)
            }
        }
        .frame(width: markSize.width, height: markSize.height * Self.dripExtent)
    }

    /// How far the drips reach, in heights of the emblem.
    private static let dripExtent: CGFloat = 1.19
    /// The icons' automatic gradients lighten each ghost toward its top.
    private static let sheen = 0.14

    private static func path(_ segments: [Segment], width: CGFloat) -> Path {
        func point(_ p: (Double, Double)) -> CGPoint {
            CGPoint(x: p.0 * width, y: p.1 * width)
        }
        var path = Path()
        for segment in segments {
            switch segment {
            case .move(let p): path.move(to: point(p))
            case .line(let p): path.addLine(to: point(p))
            case .quad(let p, let control): path.addQuadCurve(to: point(p), control: point(control))
            case .cubic(let p, let c1, let c2): path.addCurve(to: point(p), control1: point(c1), control2: point(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    private enum Segment: Sendable {
        case move((Double, Double))
        case line((Double, Double))
        /// To a point, through a control point.
        case quad((Double, Double), (Double, Double))
        /// To a point, through two control points.
        case cubic((Double, Double), (Double, Double), (Double, Double))
        case close
    }

    // In `NativeMark`'s units: widths of the emblem from its top-left corner.

    private static let upperEyes: [Segment] = [
        .move((0.61745, 0.05024)),
        .cubic((0.64067, 0.05517), (0.62074, 0.03476), (0.64396, 0.03969)),
        .line((0.63464, 0.08355)),
        .cubic((0.61142, 0.07861), (0.63135, 0.09903), (0.60813, 0.09409)),
        .close,
        .move((0.66624, 0.05024)),
        .cubic((0.68946, 0.05517), (0.66953, 0.03476), (0.69275, 0.03969)),
        .line((0.68343, 0.08355)),
        .cubic((0.66021, 0.07861), (0.68014, 0.09903), (0.65692, 0.09409)),
        .close
    ]

    private static let upperDrips: [Segment] = [
        .move((0.58253, 0.55611)),
        .quad((0.60231, 0.57457), (0.5944, 0.57062)),
        .line((0.60231, 0.62204)),
        .cubic((0.63264, 0.62336), (0.60231, 0.64973), (0.63264, 0.65105)),
        .line((0.63264, 0.58248)),
        .quad((0.66165, 0.58512), (0.64846, 0.5904)),
        .line((0.66165, 0.66292)),
        .cubic((0.69461, 0.66292), (0.66165, 0.69193), (0.69461, 0.69193)),
        .line((0.69461, 0.57721)),
        .quad((0.72099, 0.56534), (0.7078, 0.57193)),
        .line((0.72099, 0.60622)),
        .cubic((0.74868, 0.60622), (0.72099, 0.63259), (0.74868, 0.63259)),
        .line((0.74868, 0.54161)),
        .close
    ]

    private static let lowerEyes: [Segment] = [
        .move((0.30905, 0.12426)),
        .cubic((0.33208, 0.11852), (0.30522, 0.1089), (0.32825, 0.10316)),
        .line((0.3391, 0.14667)),
        .cubic((0.31607, 0.15241), (0.34293, 0.16202), (0.3199, 0.16776)),
        .close,
        .move((0.35784, 0.12426)),
        .cubic((0.38087, 0.11852), (0.35401, 0.1089), (0.37704, 0.10316)),
        .line((0.38789, 0.14667)),
        .cubic((0.36486, 0.15241), (0.39172, 0.16202), (0.36869, 0.16776)),
        .close
    ]

    private static let lowerDrips: [Segment] = [
        .move((0.25946, 0.61413)),
        .quad((0.27133, 0.65896), (0.27001, 0.62995)),
        .line((0.27133, 0.68798)),
        .cubic((0.30297, 0.68798), (0.27133, 0.71435), (0.30297, 0.71699)),
        .line((0.30297, 0.64973)),
        .quad((0.33199, 0.65105), (0.32012, 0.6616)),
        .line((0.33199, 0.73281)),
        .cubic((0.36759, 0.73281), (0.33199, 0.76182), (0.36759, 0.76182)),
        .line((0.36759, 0.64842)),
        .quad((0.39264, 0.63391), (0.38473, 0.64314)),
        .line((0.39264, 0.67347)),
        .cubic((0.42561, 0.67479), (0.39264, 0.70512), (0.42561, 0.70248)),
        .line((0.42561, 0.61545)),
        .close
    ]
}

#Preview("Halloween mark") {
    DSPreviewPair {
        HStack(spacing: DS.Space.xxl) {
            ForEach(NativeHalloweenEdition.allCases, id: \.self) { edition in
                NativeHalloweenMark(edition: edition)
                    .frame(width: 96, height: 62)
            }
        }
        .padding(DS.Space.xxl)
    }
}
