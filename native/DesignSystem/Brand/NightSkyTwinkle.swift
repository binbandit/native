import QuartzCore
import SwiftUI

/// The night sky's moving parts as a mask for `LayerMaskedView`: every star twinkling on its own
/// period and, on Halloween, the two bats drifting by the moon. Laid out like `NightSkyField`, on
/// the icon's 1024-unit canvas stretched to the bounds.
nonisolated final class NightSkyTwinkleLayer: CALayer {
    private let isHalloween: Bool
    private var laidOutSize = CGSize.zero

    /// Keyframes per second for the sampled curves; Core Animation interpolates between them.
    private static let samplesPerSecond = 20.0

    init(isHalloween: Bool) {
        self.isHalloween = isHalloween
        super.init()
    }

    override init(layer: Any) {
        isHalloween = (layer as? NightSkyTwinkleLayer)?.isHalloween ?? false
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        makeSky()
    }

    private func makeSky() {
        sublayers = nil
        let unit = CGSize(width: bounds.width / 1024, height: bounds.height / 1024)
        let scale = min(unit.width, unit.height)
        for (index, star) in NightSkyField.stars.enumerated() {
            let layer = Self.shape(star.path(unit: unit, scale: scale))
            let period = NightSkyField.twinklePeriod(index: index)
            layer.add(
                Self.loop("opacity", period) { NightSkyField.brightness(index: index, time: $0) },
                forKey: "twinkle")
            addSublayer(layer)
        }
        guard isHalloween else { return }
        let moon = NightSkyField.moonCenter(unit: unit)
        for flyer in HalloweenNight.flyers {
            let center = CGPoint(x: moon.x + flyer.x * scale, y: moon.y + flyer.y * scale)
            let layer = Self.shape(HalloweenNight.bat(center: center, width: flyer.width * scale))
            layer.opacity = Float(HalloweenNight.flyerOpacity)
            layer.add(
                Self.loop("transform.translation.x", flyer.period) {
                    HalloweenNight.drift(of: flyer, at: $0) * 6 * scale
                }, forKey: "driftX")
            layer.add(
                Self.loop("transform.translation.y", flyer.period) {
                    HalloweenNight.drift(of: flyer, at: $0) * 2 * scale
                }, forKey: "driftY")
            addSublayer(layer)
        }
    }

    private static func shape(_ path: Path) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.fillColor = CGColor(gray: 0, alpha: 1)
        return layer
    }

    /// `value` over one `period` seconds, repeated for good. Every loop the sky starts begins at the same
    /// moment, so the stars keep their phases against each other.
    private static func loop(_ keyPath: String, _ period: Double, _ value: (Double) -> Double) -> CAKeyframeAnimation {
        let samples = Int((period * samplesPerSecond).rounded())
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = (0...samples).map { value(period * Double($0) / Double(samples)) }
        animation.duration = period
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = .dsAmbient
        return animation
    }
}
