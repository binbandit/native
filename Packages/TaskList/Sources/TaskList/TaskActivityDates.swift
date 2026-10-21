import Foundation
import Observation

/// Activity known even when a task's transcript isn't open. Reading a task or receiving an older
/// listing never makes it newer or discards a prompt the host already reported.
@MainActor
@Observable
public final class TaskActivityDates<Key: Hashable> {
    private var dates: [Key: Date] = [:]

    public init() {}

    /// Metadata-only summaries can repeat or omit the date, so only newer activity notifies readers.
    public func record(_ date: Date?, for key: Key) {
        guard let date, dates[key].map({ date > $0 }) ?? true else { return }
        dates[key] = date
    }

    /// Listings cover tasks the host hasn't seen; live dates also cover sessions running in-app.
    public func date(for key: Key, listed: Date? = nil, live: Date? = nil) -> Date? {
        [dates[key], listed, live].compactMap { $0 }.max()
    }
}
