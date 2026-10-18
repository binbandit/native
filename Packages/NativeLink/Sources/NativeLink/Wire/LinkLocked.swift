import Synchronization

/// A value behind a lock that closures can share: `Mutex` itself can't be captured, so this holds one.
final class LinkLocked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        try mutex.withLock { try body(&$0) }
    }

    var value: Value { mutex.withLock { $0 } }
}
