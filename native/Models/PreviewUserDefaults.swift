#if DEBUG
import Foundation

/// Defaults kept in memory, for previews: models built on it never read or change the user's
/// settings. `UserDefaults` funnels its typed getters and setters through these three methods.
nonisolated final class PreviewUserDefaults: UserDefaults {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }

    override func set(_ value: Any?, forKey key: String) {
        lock.withLock { values[key] = value }
    }

    override func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { values }
    }

    override func removeObject(forKey key: String) {
        lock.withLock { values[key] = nil }
    }
}
#endif
