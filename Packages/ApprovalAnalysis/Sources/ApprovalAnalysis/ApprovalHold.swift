/// The same deliberate confirmation for pointer, touch and keyboard. Times are monotonic seconds
/// supplied by the host, making release, cancellation and duplicate events deterministic in tests.
public struct ApprovalHold: Equatable, Sendable {
    public static let duration: Double = 0.6
    public static let acknowledgementDuration: Double = 0.4
    public static let confirmationDuration: Double = 5
    public enum State: Equatable, Sendable {
        case idle, holding(since: Double), confirming(until: Double), allowed(at: Double)
    }
    public private(set) var state: State = .idle
    public init() {}

    public mutating func begin(at time: Double) {
        guard case .idle = state else { return }
        state = .holding(since: time)
    }

    public mutating func cancel() {
        if case .allowed = state { return }
        state = .idle
    }

    @discardableResult public mutating func advance(to time: Double) -> Bool {
        if case .holding(let start) = state, time - start >= Self.duration {
            state = .allowed(at: time)
            return true
        }
        if case .confirming(let until) = state, time >= until { state = .idle }
        return false
    }

    @discardableResult public mutating func accessibleActivate(at time: Double) -> Bool {
        if case .allowed = state { return false }
        if case .confirming(let until) = state, time < until {
            state = .allowed(at: time)
            return true
        }
        state = .confirming(until: time + Self.confirmationDuration)
        return false
    }

    public func progress(at time: Double) -> Double {
        switch state {
        case .holding(let start): min(1, max(0, (time - start) / Self.duration))
        case .allowed: 1
        default: 0
        }
    }
}
