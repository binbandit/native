import SwiftUI

extension View {
    /// Scatters the Nightly icon's sky around this view: four-point sparkles in two sizes, dot
    /// stars and the crescent moon top right, twinkling slowly (still with Reduce Motion). The
    /// layout is fixed, taken from the icon, and spans about twice the view's size without
    /// affecting layout. Draws in the current foreground style at reduced opacity.
    ///
    ///     NativeLockup(size: 28, layout: .stacked).nightSky(isEnabled: channel == .nightly)
    ///
    /// With `isHalloween`, the Halloween Nightly icon's orange moon and bats take the crescent's place.
    public func nightSky(isEnabled: Bool, isHalloween: Bool = false) -> some View {
        background {
            if isEnabled {
                GeometryReader { proxy in
                    // Square like the icon, so the scatter keeps its shape around wide or tall views.
                    let side = max(proxy.size.width, proxy.size.height) * 2.2
                    NightSkyField(isHalloween: isHalloween)
                        .frame(width: side, height: side)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .accessibilityHidden(true)
            }
        }
    }
}

/// The sky, laid out on the icon's 1024-unit canvas and stretched to the frame. The moon draws once;
/// the stars twinkle and the bats drift in Core Animation (`NightSkyTwinkleLayer`), so the sky costs
/// nothing per frame.
struct NightSkyField: View {
    let isHalloween: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if reduceMotion {
            canvas(drawsStars: true)
        } else {
            ZStack {
                canvas(drawsStars: false)
                LayerMaskedView(content: Rectangle().fill(.foreground)) {
                    NightSkyTwinkleLayer(isHalloween: isHalloween)
                }
            }
        }
    }

    /// The moon, and with `drawsStars` the stars and bats held still.
    private func canvas(drawsStars: Bool) -> some View {
        Canvas { context, size in
            let unit = CGSize(width: size.width / 1024, height: size.height / 1024)
            // Shapes keep their proportions; only their positions stretch.
            let shapeScale = min(unit.width, unit.height)
            if drawsStars {
                context.opacity = Self.stillBrightness
                for star in Self.stars {
                    context.fill(star.path(unit: unit, scale: shapeScale), with: .foreground)
                }
            }
            guard !isHalloween else {
                HalloweenNight.draw(
                    in: context,
                    moonCenter: Self.moonCenter(unit: unit),
                    scale: shapeScale,
                    isDark: colorScheme == .dark,
                    drawsFlyers: drawsStars
                )
                return
            }
            context.opacity = 0.7
            let moonHeight = 90 * shapeScale
            let center = Self.moonCenter(unit: unit)
            let moonRect = CGRect(
                x: center.x - moonHeight * Crescent.aspectRatio / 2,
                y: center.y - moonHeight / 2,
                width: moonHeight * Crescent.aspectRatio,
                height: moonHeight
            )
            context.fill(Crescent().path(in: moonRect), with: .foreground)
        }
    }

    nonisolated static func moonCenter(unit: CGSize) -> CGPoint {
        CGPoint(x: 801 * unit.width, y: 174 * unit.height)
    }

    /// Every star's brightness with Reduce Motion.
    nonisolated static let stillBrightness = 0.55

    /// How long a star takes to twinkle once; each has its own.
    nonisolated static func twinklePeriod(index: Int) -> TimeInterval {
        3.2 + Double(index % 5) * 0.55
    }

    /// A slow twinkle, each star on its own phase and period, `time` seconds in.
    nonisolated static func brightness(index: Int, time: TimeInterval) -> Double {
        let phase = Double(index) * 1.618
        let wave = 0.5 + 0.5 * sin(2 * .pi * time / twinklePeriod(index: index) + phase)
        return 0.25 + 0.5 * wave
    }

    /// The icon's four-point star: points at `radius`, waist at a quarter of it on the diagonals.
    nonisolated static func sparkle(center: CGPoint, radius: CGFloat) -> Path {
        let waist = radius / 4
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addLine(to: CGPoint(x: center.x + waist, y: center.y - waist))
        path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + waist, y: center.y + waist))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        path.addLine(to: CGPoint(x: center.x - waist, y: center.y + waist))
        path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
        path.addLine(to: CGPoint(x: center.x - waist, y: center.y - waist))
        path.closeSubpath()
        return path
    }

    nonisolated struct Star: Sendable {
        let x: Double
        let y: Double
        let radius: Double
        let isDot: Bool

        /// The star's shape on a canvas `unit` points per icon unit, its size scaled by `scale`.
        func path(unit: CGSize, scale: CGFloat) -> Path {
            let center = CGPoint(x: x * unit.width, y: y * unit.height)
            let radius = max(radius * scale, isDot ? 0.75 : 2)
            let square = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            return isDot ? Path(ellipseIn: square) : NightSkyField.sparkle(center: center, radius: radius)
        }
    }

    /// Sparkles and dots from `design/app-icon/Nightly.icon/Assets/night-sky.svg`.
    nonisolated static let stars: [Star] = [
        Star(x: 185, y: 204, radius: 16, isDot: false), Star(x: 849, y: 761, radius: 12, isDot: false),
        Star(x: 133, y: 160, radius: 7, isDot: false), Star(x: 299, y: 130, radius: 4, isDot: false),
        Star(x: 450, y: 195, radius: 5, isDot: false), Star(x: 610, y: 124, radius: 4, isDot: false),
        Star(x: 714, y: 243, radius: 5, isDot: false), Star(x: 918, y: 339, radius: 5, isDot: false),
        Star(x: 105, y: 400, radius: 5, isDot: false), Star(x: 920, y: 602, radius: 6, isDot: false),
        Star(x: 144, y: 760, radius: 5, isDot: false), Star(x: 300, y: 878, radius: 5, isDot: false),
        Star(x: 511, y: 827, radius: 7, isDot: false), Star(x: 710, y: 899, radius: 5, isDot: false),
        Star(x: 226, y: 115, radius: 2.8, isDot: true), Star(x: 371, y: 240, radius: 2, isDot: true),
        Star(x: 550, y: 171, radius: 2.5, isDot: true), Star(x: 687, y: 177, radius: 2, isDot: true),
        Star(x: 906, y: 270, radius: 2.5, isDot: true), Star(x: 126, y: 581, radius: 2.5, isDot: true),
        Star(x: 894, y: 466, radius: 2, isDot: true), Star(x: 221, y: 837, radius: 2.5, isDot: true),
        Star(x: 415, y: 916, radius: 2, isDot: true), Star(x: 630, y: 866, radius: 2.5, isDot: true),
        Star(x: 788, y: 842, radius: 2.8, isDot: true), Star(x: 889, y: 701, radius: 2, isDot: true),
    ]
}

#Preview("Night sky") {
    DSPreviewPair {
        NativeLockup(size: 28, layout: .stacked)
            .nightSky(isEnabled: true)
            .foregroundStyle(.dsTextPrimary)
            .padding(80)
    }
}
