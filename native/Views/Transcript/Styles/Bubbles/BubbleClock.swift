import Foundation

/// When each transcript row first showed up, for the times Bubbles reveals on demand. The
/// transcript doesn't carry times, so only rows that arrive while a transcript is on screen get
/// one; rows that were already there, or that arrive while history loads, could be from any time
/// and get none rather than a wrong one.
final class BubbleClock {
    static let shared = BubbleClock()

    private var dates: [String: Date] = [:]
    private var seen: Set<String> = []

    /// Notes rows by id. `live` says they arrived just now, while the transcript was showing.
    func note(_ ids: [String], live: Bool) {
        let now = Date.now
        FileHandle.standardError.write(Data("LABSCLOCK live=\(live) ids=\(ids.count) seen=\(seen.count)\n".utf8))
        for id in ids where seen.insert(id).inserted && live {
            dates[id] = now
        }
    }

    func date(for id: String) -> Date? {
        dates[id]
    }
}
