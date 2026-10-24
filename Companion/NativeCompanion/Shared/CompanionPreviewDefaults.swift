#if DEBUG
import Foundation

/// Preview interactions never read or write the phone's settings.
nonisolated final class CompanionPreviewDefaults: UserDefaults {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }

    override func set(_ value: Any?, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    override func removeObject(forKey key: String) {
        lock.withLock { values[key] = nil }
    }
}
#endif
