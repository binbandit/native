import SwiftUI

/// The Halloween Nightly icon's sky (`HalloweenNightly.icon`): an orange full moon with craters and
/// a bat across it, and two more bats flying near it. `NightSky` draws it in place of its crescent
/// during the Halloween season; the bats drift slowly (`NightSkyTwinkleLayer`), and hold still with
/// Reduce Motion.
enum HalloweenNight {
    /// Draws into a night-sky field laid out on the icon's 1024-unit canvas, around `moonCenter`;
    /// without `drawsFlyers` when Core Animation flies the bats (`NightSkyTwinkleLayer`).
    static func draw(
        in context: GraphicsContext,
        moonCenter: CGPoint,
        scale: CGFloat,
        isDark: Bool,
        drawsFlyers: Bool = true
    ) {
        let colors = NativeHalloweenEdition.moonColors(isDark: isDark)
        let radius = moonRadius * scale
        var context = context
        context.opacity = 1
        context.fill(Path(ellipseIn: square(center: moonCenter, radius: radius)), with: .color(colors.moon))
        for crater in craters {
            let center = CGPoint(x: moonCenter.x + crater.x * radius, y: moonCenter.y + crater.y * radius)
            context.fill(
                Path(ellipseIn: square(center: center, radius: crater.radius * radius)), with: .color(colors.craters))
        }
        // The icon's bat spans 43% of the moon, a little up and left of its center.
        let batWidth = radius * 0.87
        let batCenter = CGPoint(x: moonCenter.x - radius * 0.09, y: moonCenter.y - radius * 0.07)
        context.fill(bat(center: batCenter, width: batWidth), with: .color(colors.bat))

        guard drawsFlyers else { return }
        context.opacity = flyerOpacity
        for flyer in flyers {
            let center = CGPoint(x: moonCenter.x + flyer.x * scale, y: moonCenter.y + flyer.y * scale)
            context.fill(bat(center: center, width: flyer.width * scale), with: .foreground)
        }
    }

    /// The flying bats are part of the sky, so they draw in its color, quieter than the stars.
    nonisolated static let flyerOpacity = 0.45

    /// How far a flying bat has drifted `time` seconds in, from -1 to 1; it moves 6 units across and 2
    /// down for each.
    nonisolated static func drift(of flyer: Flyer, at time: TimeInterval) -> CGFloat {
        sin(2 * .pi * time / flyer.period + flyer.phase)
    }

    private static let moonRadius: CGFloat = 52

    private struct Crater {
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
    }

    /// `moon-detail.svg`, in radii of the moon from its center.
    private static let craters = [
        Crater(x: 0.377, y: -0.434, radius: 0.139),
        Crater(x: 0.525, y: -0.164, radius: 0.074),
        Crater(x: 0.189, y: -0.557, radius: 0.049),
        Crater(x: -0.426, y: 0.336, radius: 0.082),
    ]

    nonisolated struct Flyer: Sendable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let period: Double
        let phase: Double
    }

    /// Two bats down and left of the moon, in the canvas's units from its center.
    nonisolated static let flyers = [
        Flyer(x: -150, y: 18, width: 34, period: 9, phase: 0),
        Flyer(x: -104, y: 92, width: 24, period: 11.5, phase: 2.1),
    ]

    private static func square(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// `moon-bats.svg`'s bat, about twice as wide as it is tall, centered on `center`.
    nonisolated static func bat(center: CGPoint, width: CGFloat) -> Path {
        let height = width * batAspect
        let origin = CGPoint(x: center.x - width / 2, y: center.y - height / 2)
        func point(_ p: (Double, Double)) -> CGPoint {
            CGPoint(x: origin.x + p.0 * width, y: origin.y + p.1 * height)
        }
        var path = Path()
        for segment in batOutline {
            switch segment {
            case .move(let p): path.move(to: point(p))
            case .line(let p): path.addLine(to: point(p))
            case .cubic(let p, let c1, let c2): path.addCurve(to: point(p), control1: point(c1), control2: point(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }

    private nonisolated static let batAspect: CGFloat = 54.0 / 106.0

    private enum Segment: Sendable {
        case move((Double, Double))
        case line((Double, Double))
        /// To a point, through two control points.
        case cubic((Double, Double), (Double, Double), (Double, Double))
        case close
    }

    /// In fractions of the bat's width and height, from its top-left corner.
    private nonisolated static let batOutline: [Segment] = [
        .move((0.0, 0.6667)),
        .cubic((0.2547, 0.0), (0.1038, 0.5556), (0.2075, 0.2778)),
        .cubic((0.4245, 0.4074), (0.3679, 0.0741), (0.4057, 0.2963)),
        .line((0.4528, 0.1852)),
        .line((0.5, 0.3148)),
        .line((0.5472, 0.1852)),
        .line((0.5755, 0.4074)),
        .cubic((0.7453, 0.0), (0.5943, 0.2963), (0.6321, 0.0741)),
        .cubic((1.0, 0.6667), (0.7925, 0.2778), (0.8962, 0.5556)),
        .cubic((0.7547, 0.8333), (0.8019, 0.5741), (0.7736, 0.9074)),
        .cubic((0.5943, 0.8333), (0.6509, 0.5741), (0.6038, 0.8519)),
        .cubic((0.5, 1.0), (0.5377, 0.7778), (0.5189, 0.963)),
        .cubic((0.4057, 0.8333), (0.4811, 0.963), (0.4623, 0.7778)),
        .cubic((0.2453, 0.8333), (0.3962, 0.8519), (0.3491, 0.5741)),
        .cubic((0.0, 0.6667), (0.2264, 0.9074), (0.1981, 0.5741)),
        .close,
    ]
}
