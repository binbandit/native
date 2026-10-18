import SwiftUI

/// The Día de Muertos edition of Native's emblem, for Home: the links in cempasúchil orange and a
/// channel color, warmed by candlelight, with a string of papel picado above and an ofrenda of
/// marigolds between two votive candles below. Original artwork after the visual direction in
/// `docs/celebrations.md`: remembrance and affection, never a party.
///
/// It lays out exactly like `NativeMark`, so it can stand in for it; the flags rise above that frame
/// and the ofrenda sits below it, without affecting layout.
public struct NativeMuertosMark: View {
    let edition: NativeMuertosEdition

    @Environment(\.colorScheme) private var colorScheme

    public init(edition: NativeMuertosEdition) {
        self.edition = edition
    }

    public var body: some View {
        Color.clear
            .aspectRatio(NativeMark.aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    Canvas { context, _ in
                        draw(in: &context, width: width)
                    }
                    .frame(width: width, height: width * (Self.rise + 1 / NativeMark.aspectRatio + Self.fall))
                    .offset(y: -width * Self.rise)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Native")
            .accessibilityAddTraits(.isImage)
    }

    // The artwork, in widths of the emblem from its top-left corner.

    /// How far the flags reach above the emblem, and the ofrenda below it.
    private static let rise: CGFloat = 0.235
    private static let fall: CGFloat = 0.125

    private func draw(in context: inout GraphicsContext, width: CGFloat) {
        let palette = edition.palette(isDark: colorScheme == .dark)
        // Paths are built in emblem units and scaled to points as they're filled: scaling the context
        // instead would flatten the small curves (petals, flames) into polygons.
        context.translateBy(x: 0, y: width * Self.rise)
        let painter = Painter(context: context, scale: width)
        let markRect = CGRect(x: 0, y: 0, width: 1, height: 1 / NativeMark.aspectRatio)

        // Candlelight, warm behind the links.
        painter.fill(
            Path(ellipseIn: CGRect(x: -0.12, y: -0.18, width: 1.24, height: 1.06)),
            radial: [palette.glow.opacity(palette.glowOpacity), palette.glow.opacity(0)],
            center: CGPoint(x: 0.5, y: 0.36), radius: 0.62)

        for (link, colors) in [
            (NativeMark.Link.left, palette.marigoldLink), (NativeMark.Link.right, palette.channelLink),
        ] {
            painter.fill(
                NativeMark(link: link).path(in: markRect), linear: [colors.top, colors.bottom],
                from: .zero, to: CGPoint(x: 0, y: markRect.height))
        }

        drawPapelPicado(with: painter, palette: palette)
        for candle in Self.candles {
            drawCandle(at: candle, with: painter, palette: palette)
        }
        for blossom in Self.blossoms {
            drawMarigold(blossom, with: painter, palette: palette)
        }
    }

    /// Fills paths given in emblem units, in points.
    private struct Painter {
        let context: GraphicsContext
        let scale: CGFloat

        private var transform: CGAffineTransform { CGAffineTransform(scaleX: scale, y: scale) }

        private func point(_ point: CGPoint) -> CGPoint {
            point.applying(transform)
        }

        func fill(_ path: Path, _ color: Color, evenOdd: Bool = false) {
            context.fill(path.applying(transform), with: .color(color), style: FillStyle(eoFill: evenOdd))
        }

        func fill(_ path: Path, linear colors: [Color], from start: CGPoint, to end: CGPoint) {
            context.fill(
                path.applying(transform),
                with: .linearGradient(Gradient(colors: colors), startPoint: point(start), endPoint: point(end)))
        }

        func fill(_ path: Path, radial colors: [Color], center: CGPoint, radius: CGFloat) {
            context.fill(
                path.applying(transform),
                with: .radialGradient(
                    Gradient(colors: colors), center: point(center), startRadius: 0, endRadius: radius * scale))
        }

        func stroke(_ path: Path, _ color: Color, width: CGFloat) {
            context.stroke(path.applying(transform), with: .color(color), lineWidth: width * scale)
        }
    }

    // MARK: - Papel picado

    /// The string's ends and the control point that gives it its sag.
    private static let stringEnds: (CGPoint, CGPoint) = (CGPoint(x: 0.03, y: -0.215), CGPoint(x: 0.97, y: -0.215))
    private static let stringSag = CGPoint(x: 0.5, y: -0.085)
    private static let flagSize = CGSize(width: 0.135, height: 0.118)
    private static let flagCenters: [CGFloat] = [0.14, 0.32, 0.5, 0.68, 0.86]

    private func drawPapelPicado(with painter: Painter, palette: NativeMuertosEdition.Palette) {
        var string = Path()
        string.move(to: Self.stringEnds.0)
        string.addQuadCurve(to: Self.stringEnds.1, control: Self.stringSag)
        painter.stroke(string, palette.string, width: 0.006)

        for (index, x) in Self.flagCenters.enumerated() {
            let top = Self.stringY(at: x) - 0.004
            let rect = CGRect(
                x: x - Self.flagSize.width / 2, y: top, width: Self.flagSize.width, height: Self.flagSize.height)
            var flag = Self.flagOutline(rect)
            flag.addPath(index.isMultiple(of: 2) ? Self.flowerCut(in: rect) : Self.diamondCut(in: rect))
            // Even-odd, so the cuts are holes the page shows through, like cut tissue paper.
            painter.fill(flag, palette.flags[index % palette.flags.count], evenOdd: true)
        }
    }

    /// Where the sagging string is at `x`, from its quadratic curve.
    private static func stringY(at x: CGFloat) -> CGFloat {
        let (start, end) = stringEnds
        let t = (x - start.x) / (end.x - start.x)
        return (1 - t) * (1 - t) * start.y + 2 * t * (1 - t) * stringSag.y + t * t * end.y
    }

    /// A flag hanging from its top edge, with a scalloped hem.
    private static func flagOutline(_ rect: CGRect) -> Path {
        var path = Path()
        let scallops = 4
        let hem = rect.maxY - rect.height * 0.14
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: hem))
        let step = rect.width / CGFloat(scallops)
        for index in (0..<scallops).reversed() {
            let left = rect.minX + step * CGFloat(index)
            path.addQuadCurve(
                to: CGPoint(x: left, y: hem), control: CGPoint(x: left + step / 2, y: rect.maxY + rect.height * 0.12))
        }
        path.closeSubpath()
        return path
    }

    /// A four-petal flower with a round heart, cut from the middle of the flag, and two pinpricks.
    private static func flowerCut(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.42)
        let petal = rect.width * 0.15
        for angle in stride(from: 0.0, to: 2 * Double.pi, by: Double.pi / 2) {
            let offset = CGPoint(x: cos(angle) * petal * 1.05, y: sin(angle) * petal * 1.05)
            path.addEllipse(
                in: CGRect(
                    x: center.x + offset.x - petal * 0.62, y: center.y + offset.y - petal * 0.62, width: petal * 1.24,
                    height: petal * 1.24))
        }
        path.addEllipse(in: CGRect(x: center.x - petal * 0.42, y: center.y - petal * 0.42, width: petal * 0.84, height: petal * 0.84))
        path.addPath(pinpricks(in: rect))
        return path
    }

    /// A diamond with a smaller diamond left standing inside it, and two pinpricks.
    private static func diamondCut(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.42)
        for (half, isInner) in [(rect.width * 0.24, false), (rect.width * 0.1, true)] {
            let tall = half * (isInner ? 1.25 : 1.15)
            path.move(to: CGPoint(x: center.x, y: center.y - tall))
            path.addLine(to: CGPoint(x: center.x + half, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + tall))
            path.addLine(to: CGPoint(x: center.x - half, y: center.y))
            path.closeSubpath()
        }
        path.addPath(pinpricks(in: rect))
        return path
    }

    private static func pinpricks(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width * 0.045
        for x in [rect.minX + rect.width * 0.16, rect.maxX - rect.width * 0.16] {
            path.addEllipse(
                in: CGRect(x: x - radius, y: rect.minY + rect.height * 0.16 - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }

    // MARK: - Ofrenda

    private struct Blossom {
        let center: CGPoint
        let radius: CGFloat
        /// Turns each flower a little so the three don't look stamped.
        let turn: Double
    }

    private static let blossoms = [
        Blossom(center: CGPoint(x: 0.398, y: 0.7), radius: 0.052, turn: 0.2),
        Blossom(center: CGPoint(x: 0.628, y: 0.694), radius: 0.05, turn: 0.5),
        Blossom(center: CGPoint(x: 0.513, y: 0.688), radius: 0.064, turn: 0),
    ]

    private static let candles = [CGPoint(x: 0.285, y: 0.692), CGPoint(x: 0.745, y: 0.686)]

    /// Cempasúchil: ruffled rings of petals, darker outside, golden toward a deep heart.
    private func drawMarigold(_ blossom: Blossom, with painter: Painter, palette: NativeMuertosEdition.Palette) {
        let rings: [(count: Int, distance: CGFloat, size: CGSize, color: Color)] = [
            (13, 0.6, CGSize(width: 0.5, height: 0.66), palette.petals.outer),
            (11, 0.36, CGSize(width: 0.44, height: 0.54), palette.petals.outer.mix(with: palette.petals.inner, by: 0.55)),
            (8, 0.16, CGSize(width: 0.36, height: 0.42), palette.petals.inner),
        ]
        for (ringIndex, ring) in rings.enumerated() {
            var petals = Path()
            for index in 0..<ring.count {
                let angle = blossom.turn + Double(ringIndex) * 0.4 + Double(index) / Double(ring.count) * 2 * .pi
                let petal = Path(
                    ellipseIn: CGRect(
                        x: -ring.size.width * blossom.radius / 2, y: -(ring.distance + ring.size.height / 2) * blossom.radius,
                        width: ring.size.width * blossom.radius, height: ring.size.height * blossom.radius))
                petals.addPath(
                    petal,
                    transform: CGAffineTransform(rotationAngle: angle)
                        .concatenating(CGAffineTransform(translationX: blossom.center.x, y: blossom.center.y)))
            }
            painter.fill(petals, ring.color)
        }
        let heart = blossom.radius * 0.17
        painter.fill(
            Path(ellipseIn: CGRect(x: blossom.center.x - heart, y: blossom.center.y - heart, width: heart * 2, height: heart * 2)),
            palette.petals.heart)
    }

    /// A votive: a short cream candle and a flame with its own halo.
    private func drawCandle(at base: CGPoint, with painter: Painter, palette: NativeMuertosEdition.Palette) {
        let body = CGRect(x: base.x - 0.017, y: base.y - 0.012, width: 0.034, height: 0.05)
        let flameTip = CGPoint(x: base.x, y: body.minY - 0.05)
        painter.fill(
            Path(ellipseIn: CGRect(x: flameTip.x - 0.05, y: flameTip.y - 0.025, width: 0.1, height: 0.1)),
            radial: [palette.flame.outer.opacity(0.45), palette.flame.outer.opacity(0)],
            center: CGPoint(x: flameTip.x, y: flameTip.y + 0.03), radius: 0.05)
        painter.fill(Path(roundedRect: body, cornerRadius: 0.006), palette.wax)
        var flame = Path()
        flame.move(to: flameTip)
        flame.addQuadCurve(to: CGPoint(x: base.x, y: body.minY - 0.004), control: CGPoint(x: base.x + 0.024, y: body.minY - 0.016))
        flame.addQuadCurve(to: flameTip, control: CGPoint(x: base.x - 0.024, y: body.minY - 0.016))
        painter.fill(flame, palette.flame.outer)
        painter.fill(
            Path(ellipseIn: CGRect(x: base.x - 0.006, y: body.minY - 0.024, width: 0.012, height: 0.018)),
            palette.flame.core)
    }
}

#Preview("Día de Muertos mark") {
    DSPreviewPair {
        HStack(spacing: DS.Space.xxl) {
            ForEach(NativeMuertosEdition.allCases, id: \.self) { edition in
                NativeMuertosMark(edition: edition)
                    .frame(width: 96, height: 62)
            }
        }
        .padding(DS.Space.xxxl)
    }
}
