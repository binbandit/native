import QuartzCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A dot-grid loader animated by Core Animation, in the render server, rather than redrawn by
/// SwiftUI every frame: a SwiftUI animation that never stops re-renders the whole window it's in
/// on every frame, which for one working indicator cost half a CPU core and 225 MB of graphics
/// memory for as long as an agent worked. The pulsing dots mask a fill in the foreground style,
/// which SwiftUI draws once.
struct DotGridPulse: View {
    let pattern: DotGridLoader.Pattern

    var body: some View {
        DotGridPulseView(pattern: pattern)
    }
}

/// The fill the dots show, in whatever foreground style the loader is given.
private func dotGridFill(in environment: EnvironmentValues) -> AnyView {
    AnyView(Rectangle().fill(.foreground).environment(\.self, environment))
}

#if canImport(AppKit)
private struct DotGridPulseView: NSViewRepresentable {
    let pattern: DotGridLoader.Pattern

    func makeNSView(context: Context) -> DotGridPulseHost {
        DotGridPulseHost(pattern: pattern, fill: dotGridFill(in: context.environment))
    }

    func updateNSView(_ host: DotGridPulseHost, context: Context) {
        host.update(pattern: pattern, fill: dotGridFill(in: context.environment))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DotGridPulseHost, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

final class DotGridPulseHost: NSView {
    private let fill: NSHostingView<AnyView>
    private let dots: DotGridPulseLayer

    init(pattern: DotGridLoader.Pattern, fill: AnyView) {
        self.fill = NSHostingView(rootView: fill)
        dots = DotGridPulseLayer(pattern: pattern)
        super.init(frame: .zero)
        self.fill.sizingOptions = []
        wantsLayer = true
        addSubview(self.fill)
        // AppKit layers count y up; the pattern counts it down, as SwiftUI does.
        dots.isGeometryFlipped = true
        layer?.mask = dots
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(pattern: DotGridLoader.Pattern, fill: AnyView) {
        self.fill.rootView = fill
        if dots.pattern != pattern {
            dots.pattern = pattern
        }
    }

    override func layout() {
        super.layout()
        fill.frame = bounds
        dots.frame = bounds
    }
}
#else
private struct DotGridPulseView: UIViewRepresentable {
    let pattern: DotGridLoader.Pattern

    func makeUIView(context: Context) -> DotGridPulseHost {
        DotGridPulseHost(pattern: pattern, fill: dotGridFill(in: context.environment))
    }

    func updateUIView(_ host: DotGridPulseHost, context: Context) {
        host.update(pattern: pattern, fill: dotGridFill(in: context.environment))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DotGridPulseHost, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

final class DotGridPulseHost: UIView {
    private let fill: UIHostingController<AnyView>
    private let dots: DotGridPulseLayer

    init(pattern: DotGridLoader.Pattern, fill: AnyView) {
        self.fill = UIHostingController(rootView: fill)
        dots = DotGridPulseLayer(pattern: pattern)
        super.init(frame: .zero)
        self.fill.sizingOptions = []
        self.fill.view.backgroundColor = .clear
        addSubview(self.fill.view)
        layer.mask = dots
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(pattern: DotGridLoader.Pattern, fill: AnyView) {
        self.fill.rootView = fill
        if dots.pattern != pattern {
            dots.pattern = pattern
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        fill.view.frame = bounds
        dots.frame = bounds
    }
}
#endif

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
