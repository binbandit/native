import QuartzCore
import SwiftUI

/// One persistent mask lets the same dots gather into an ask, contract into unread, or fade on
/// read. Loops run in Core Animation, with a finite breath duration and no per-row SwiftUI timer.
nonisolated final class TaskSignalLayer: CALayer {
    private struct State: Equatable {
        var status: TaskStatus
        var unread: Bool
        var showsRest: Bool
        var offline: Bool
        var reduceMotion: Bool
        var breathUntil: Date?
    }

    private var signal: State?
    private var dots: [CALayer] = []
    private var transitionFrom: State?

    override init() {
        super.init()
        for _ in 0..<9 {
            let dot = CALayer()
            dot.backgroundColor = CGColor(gray: 0, alpha: 1)
            addSublayer(dot)
            dots.append(dot)
        }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(
        status: TaskStatus, unread: Bool, showsRest: Bool, offline: Bool, reduceMotion: Bool,
        breathUntil: Date?
    ) {
        let next = State(
            status: status, unread: unread, showsRest: showsRest, offline: offline,
            reduceMotion: reduceMotion, breathUntil: breathUntil)
        guard next != signal else { return }
        transitionFrom = signal
        signal = next
        removeAnimation(forKey: "breath")
        if status.needsAttention, !offline, !reduceMotion {
            let remaining = breathUntil?.timeIntervalSinceNow ?? 0
            if remaining > 0 {
                let breath = CAKeyframeAnimation(keyPath: "opacity")
                breath.values = [1, DS.Signal.breathLow, 1]
                breath.keyTimes = [0, 0.5, 1]
                breath.timingFunctions = [.init(name: .easeInEaseOut), .init(name: .easeInEaseOut)]
                breath.duration = DS.Signal.breathPeriod
                breath.repeatDuration = remaining
                add(breath, forKey: "breath")
            }
        }
        setNeedsLayout()
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        guard let signal else { return }
        let unit = min(bounds.width, bounds.height) / DS.Signal.canvas
        guard unit > 0 else { return }
        let previous = transitionFrom
        transitionFrom = nil
        let changedShape =
            previous.map {
                $0.status != signal.status || $0.unread != signal.unread || $0.offline != signal.offline
                    || $0.showsRest != signal.showsRest
            } ?? false
        let animates = changedShape && !signal.reduceMotion
        let now = CACurrentMediaTime()
        let pattern = signal.offline ? nil : signal.status.loader
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, dot) in dots.enumerated() {
            let column = index % 3
            let row = index / 3
            let center = CGPoint(x: DS.Signal.centers[column], y: DS.Signal.centers[row])
            let fromPosition = dot.presentation()?.position ?? dot.position
            let fromRadius =
                (dot.presentation()?.bounds.width ?? dot.bounds.width) / 2
                * (dot.presentation()?.transform.m11 ?? 1)
            let fromOpacity = dot.presentation()?.opacity ?? dot.opacity
            dot.removeAllAnimations()
            let geometry = geometry(index: index, signal: signal)
            let radius = geometry.radius * unit
            dot.position = CGPoint(x: geometry.center.x * unit, y: geometry.center.y * unit)
            dot.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            dot.cornerRadius = radius
            dot.opacity = geometry.visible ? 1 : 0
            if animates {
                let duration = duration(for: signal)
                let delay =
                    signal.status == .done && signal.unread
                    ? Double(abs(column - 1) + abs(row - 1)) * DS.Signal.ringDelay : 0
                animate(
                    dot, key: "position.x", from: fromPosition.x, to: dot.position.x, duration: duration, delay: delay)
                animate(
                    dot, key: "position.y", from: fromPosition.y, to: dot.position.y, duration: duration, delay: delay)
                animate(
                    dot, key: "bounds.size.width", from: fromRadius * 2, to: radius * 2, duration: duration,
                    delay: delay)
                animate(
                    dot, key: "bounds.size.height", from: fromRadius * 2, to: radius * 2, duration: duration,
                    delay: delay)
                animate(dot, key: "cornerRadius", from: fromRadius, to: radius, duration: duration, delay: delay)
                animate(dot, key: "opacity", from: fromOpacity, to: dot.opacity, duration: duration, delay: delay)
            }
            if let pattern, !signal.reduceMotion,
                let moving = pattern.timing.dots.first(where: { $0.x == center.x && $0.y == center.y })
            {
                let timing = pattern.timing
                let frames = Int(timing.end - timing.start)
                let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
                let rest = DS.Signal.restingRadius / DS.Signal.movingRadius
                pulse.values = (0...frames).map { rest + (1 - rest) * moving.scale(at: timing.start + Double($0)) }
                pulse.duration = Double(frames) / 60
                // An answered ask restarts at the left column; existing working rows keep one beat.
                pulse.beginTime =
                    previous?.status.needsAttention == true
                    ? now : now - now.truncatingRemainder(dividingBy: pulse.duration)
                pulse.repeatCount = .infinity
                pulse.preferredFrameRateRange = .dsMotion
                dot.add(pulse, forKey: "pulse")
            }
        }
        CATransaction.commit()
    }

    private func geometry(index: Int, signal: State) -> (center: CGPoint, radius: CGFloat, visible: Bool) {
        let column = index % 3
        let row = index / 3
        let center = CGPoint(x: DS.Signal.centers[column], y: DS.Signal.centers[row])
        if signal.offline { return (center, DS.Signal.stillRadius, true) }
        if let pattern = signal.status.loader {
            let visible = pattern.timing.dots.contains { $0.x == center.x && $0.y == center.y }
            return (center, signal.reduceMotion ? DS.Signal.movingRadius * 0.6 : DS.Signal.movingRadius, visible)
        }
        switch signal.status {
        case .needsInput, .needsPermission, .needsPlanReview: return (center, DS.Signal.stillRadius, true)
        case .failed: return (center, DS.Signal.stillRadius, column == row || column + row == 2)
        case .paused: return (center, DS.Signal.stillRadius, column != 1)
        case .limited: return (center, DS.Signal.stillRadius, row != 1 || column == 1)
        case .done where signal.unread:
            return (CGPoint(x: 120, y: 120), index == 4 ? DS.Signal.unreadRadius : 0, index == 4)
        default:
            return (CGPoint(x: 120, y: 120), DS.Signal.restRadius, signal.showsRest && index == 4)
        }
    }

    private func duration(for signal: State) -> TimeInterval {
        if signal.status.needsAttention { return DS.Signal.askDuration }
        if signal.status == .failed { return DS.Signal.failureDuration }
        if signal.status == .done, signal.unread { return DS.Signal.finishDuration }
        if !signal.status.isActive { return DS.Signal.readDuration }
        return DS.Signal.answerDuration
    }

    private func animate(_ dot: CALayer, key: String, from: Any, to: Any, duration: TimeInterval, delay: TimeInterval) {
        let animation: CABasicAnimation
        if signal?.status.needsAttention == true {
            let spring = CASpringAnimation(keyPath: key)
            spring.mass = 1
            spring.stiffness = 240
            spring.damping = 24
            animation = spring
        } else {
            animation = CABasicAnimation(keyPath: key)
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.beginTime = CACurrentMediaTime() + delay
        animation.fillMode = .backwards
        dot.add(animation, forKey: key)
    }
}
