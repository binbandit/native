import Foundation

extension PolicyLoader {
    /// The current policy, then each new one when preferences change (a profile installed or
    /// removed, or the user changing their own value). Unchanged policies aren't repeated.
    public static func updates(
        from source: any PolicySource, notificationCenter: NotificationCenter = .default
    ) -> AsyncStream<NativePolicy> {
        AsyncStream { continuation in
            let latest = LatestPolicy(load(from: source))
            continuation.yield(latest.value)
            let observer = notificationCenter.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: nil
            ) { _ in
                if let changed = latest.replace(with: load(from: source)) {
                    continuation.yield(changed)
                }
            }
            let token = ObserverToken(observer)
            continuation.onTermination = { _ in
                notificationCenter.removeObserver(token.observer)
            }
        }
    }
}

/// The last policy published, shared between notification callbacks.
private final class LatestPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var current: NativePolicy

    init(_ policy: NativePolicy) {
        current = policy
    }

    var value: NativePolicy {
        lock.withLock { current }
    }

    /// Stores `policy` and returns it when it differs from the last one.
    func replace(with policy: NativePolicy) -> NativePolicy? {
        lock.withLock {
            guard policy != current else { return nil }
            current = policy
            return policy
        }
    }
}

/// NotificationCenter's observer token, which is only used to remove the observer.
private struct ObserverToken: @unchecked Sendable {
    let observer: any NSObjectProtocol

    init(_ observer: any NSObjectProtocol) {
        self.observer = observer
    }
}
