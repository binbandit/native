import QuartzCore

/// A soft vertical band sweeping left to right across its bounds, as a mask for `LayerMaskedView`:
/// the highlight that runs over busy text. The band is 30% of the width, fading in and out from its
/// middle, and its middle travels from 30% before the leading edge to 30% past the trailing one in
/// `duration`, then starts over.
nonisolated final class ShimmerBandLayer: CALayer {
    static let duration: TimeInterval = 2

    private let band = CAGradientLayer()
    private var laidOutSize = CGSize.zero

    override init() {
        super.init()
        let opaque = CGColor(gray: 0, alpha: 1)
        let clear = CGColor(gray: 0, alpha: 0)
        band.colors = [clear, opaque, clear]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        addSublayer(band)
    }

    override init(layer: Any) {
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.bounds = CGRect(x: 0, y: 0, width: bounds.width * 0.3, height: bounds.height)
        band.position = CGPoint(x: -bounds.width * 0.3, y: bounds.midY)
        CATransaction.commit()

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bounds.width * 0.3
        sweep.toValue = bounds.width * 1.3
        sweep.duration = Self.duration
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        sweep.preferredFrameRateRange = .dsMotion
        // Every shimmer on screen on the same beat, as when they all followed the clock.
        let now = convertTime(CACurrentMediaTime(), from: nil)
        sweep.beginTime = now - now.truncatingRemainder(dividingBy: Self.duration)
        band.add(sweep, forKey: "sweep")
    }
}
