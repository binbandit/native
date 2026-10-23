/// The visible time left on an undo offer. A hover holds it indefinitely; leaving gives the user
/// at least three seconds to return. Continuous time keeps wall-clock adjustments out of dismissal.
public struct UndoToastLifetime: Sendable {
    public private(set) var deadline: ContinuousClock.Instant?
    private var remaining: Duration

    public init(duration: Duration, now: ContinuousClock.Instant = .now) {
        remaining = duration
        deadline = now.advanced(by: duration)
    }

    public mutating func setHeld(_ held: Bool, now: ContinuousClock.Instant = .now) {
        if held, let deadline {
            remaining = max(.zero, now.duration(to: deadline))
            self.deadline = nil
        } else if !held, deadline == nil {
            remaining = max(remaining, .seconds(3))
            deadline = now.advanced(by: remaining)
        }
    }
}
