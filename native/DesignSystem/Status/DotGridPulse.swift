import QuartzCore
import SwiftUI

/// A dot-grid loader animated by Core Animation (`LayerMaskedView`): the pulsing dots mask a fill in
/// the foreground style.
struct DotGridPulse: View {
    let pattern: DotGridLoader.Pattern

    var body: some View {
        LayerMaskedView(content: Rectangle().fill(.foreground)) {
            DotGridPulseLayer(pattern: pattern)
        } update: { dots in
            if dots.pattern != pattern {
                dots.pattern = pattern
            }
        }
    }
}

/// The nine dots on the loader's 240pt canvas, each pulsing on a loop Core Animation repeats.
nonisolated final class DotGridPulseLayer: CALayer {
    var pattern: DotGridLoader.Pattern {
        didSet { makeDots() }
    }

    init(pattern: DotGridLoader.Pattern) {
        self.pattern = pattern
        super.init()
        makeDots()
    }

    override init(layer: Any) {
        pattern = (layer as? DotGridPulseLayer)?.pattern ?? .typing
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func makeDots() {
        sublayers = nil
        let timing = pattern.timing
        let frames = Int(timing.end - timing.start)
        let duration = Double(frames) / 60
        // Every loader of a pattern on the same beat, as when they all followed the clock.
        let now = CACurrentMediaTime()
        for dot in timing.dots {
            let layer = CALayer()
            layer.backgroundColor = CGColor(gray: 0, alpha: 1)
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = (0...frames).map { dot.scale(at: timing.start + Double($0)) }
            pulse.duration = duration
            pulse.beginTime = now - now.truncatingRemainder(dividingBy: duration)
            pulse.repeatCount = .infinity
            pulse.isRemovedOnCompletion = false
            pulse.preferredFrameRateRange = .dsMotion
            layer.add(pulse, forKey: "pulse")
            addSublayer(layer)
        }
        setNeedsLayout()
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        let unit = min(bounds.width, bounds.height) / 240
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, dot) in zip(sublayers ?? [], pattern.timing.dots) {
            layer.bounds = CGRect(x: 0, y: 0, width: 40 * unit, height: 40 * unit)
            layer.cornerRadius = 20 * unit
            layer.position = CGPoint(x: dot.x * unit, y: dot.y * unit)
        }
        CATransaction.commit()
    }
}
