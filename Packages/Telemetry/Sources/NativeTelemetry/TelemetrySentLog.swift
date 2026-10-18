import Foundation

/// A local, readable record of every batch sent, newest last, for Settings ▸ Privacy. Bounded, so
/// it never grows without limit.
public final class TelemetrySentLog: Sendable {
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var id = UUID()
        public var date = Date.now
        public var destination: TelemetryDestinationID
        public var resource: TelemetryResource
        public var records: [TelemetryRecord]
    }

    public let url: URL
    private let limit: Int
    private let lock = NSLock()

    public init(url: URL, limit: Int = 200) {
        self.url = url
        self.limit = limit
    }

    public func append(_ entry: Entry) {
        lock.withLock {
            var entries = read()
            entries.append(entry)
            write(Array(entries.suffix(limit)))
        }
    }

    public func entries() -> [Entry] {
        lock.withLock { read() }
    }

    public func clear() {
        lock.withLock { try? FileManager.default.removeItem(at: url) }
    }

    private func read() -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Entry.self, from: Data($0)) }
    }

    private func write(_ entries: [Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        var data = Data()
        for entry in entries {
            guard let line = try? encoder.encode(entry) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
